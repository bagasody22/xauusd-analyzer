import 'dart:math';
import 'analyzer_engine.dart';

enum ScalpTimeframe { m1, m5 }

enum ScalpSignal { buy, sell, noEntry }

class ScalpResult {
  final ScalpTimeframe timeframe;
  final ScalpSignal signal;
  final double currentPrice;
  final double? stopLoss;
  final double? takeProfit;
  final double riskRewardRatio;
  final double nearestSupport;
  final double nearestResistance;
  final String zoneInfo;
  final List<String> reasons;

  const ScalpResult({
    required this.timeframe,
    required this.signal,
    required this.currentPrice,
    this.stopLoss,
    this.takeProfit,
    this.riskRewardRatio = 2.0,
    required this.nearestSupport,
    required this.nearestResistance,
    required this.zoneInfo,
    required this.reasons,
  });
}

class ShortTermAnalyzer {
  static ScalpResult evaluate({
    required ScalpTimeframe timeframe,
    required List<Candle> candles,
    required double ema50,
    required double ema200,
    required double adx,
    required double atr,
    double minAdx = 22.0,
    double slMultiplier = 0.9,
  }) {
    final currentPrice = candles.last.close;

    // Deteksi SNR jarak dekat (20 candle terakhir)
    final window = candles.sublist(max(0, candles.length - 20));
    double swingHigh = window.first.high;
    double swingLow = window.first.low;
    for (final c in window) {
      if (c.high > swingHigh) swingHigh = c.high;
      if (c.low < swingLow) swingLow = c.low;
    }

    // Deteksi SnD jarak dekat (candle impulsif di 20 candle terakhir)
    double? demandLow;
    double? demandHigh;
    double? supplyLow;
    double? supplyHigh;

    for (int i = 1; i < window.length - 1; i++) {
      final prev = window[i - 1];
      final curr = window[i];
      final body = (curr.close - curr.open).abs();

      if (curr.close > curr.open && body > atr * 1.15) {
        demandLow = prev.low;
        demandHigh = max(prev.open, prev.close);
      }
      if (curr.close < curr.open && body > atr * 1.15) {
        supplyLow = min(prev.open, prev.close);
        supplyHigh = prev.high;
      }
    }

    final nearestSupport =
        demandLow != null ? min(swingLow, demandLow) : swingLow;
    final nearestResistance =
        supplyHigh != null ? max(swingHigh, supplyHigh) : swingHigh;

    final reasons = <String>[];

    if (atr <= 0) {
      reasons.add('ATR tidak valid; tahan entry untuk menjaga manajemen risiko.');
      return ScalpResult(
        timeframe: timeframe,
        signal: ScalpSignal.noEntry,
        currentPrice: currentPrice,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: 'Data volatilitas tidak valid',
        reasons: reasons,
      );
    }

    // Filter lonjakan volatilitas ekstrem pada 20 candle terakhir
    double trSum = 0;
    int trCount = 0;
    for (int i = max(1, candles.length - 20); i < candles.length; i++) {
      final h = candles[i].high;
      final l = candles[i].low;
      final pc = candles[i - 1].close;
      trSum += max(h - l, max((h - pc).abs(), (l - pc).abs()));
      trCount++;
    }
    final avgRecentAtr = trCount > 0 ? trSum / trCount : atr;
    if (avgRecentAtr > 0 && atr > avgRecentAtr * 2.4) {
      reasons.add(
        'Lonjakan volatilitas ekstrem terdeteksi (ATR ${atr.toStringAsFixed(2)}); hindari spike jangka pendek.',
      );
      return ScalpResult(
        timeframe: timeframe,
        signal: ScalpSignal.noEntry,
        currentPrice: currentPrice,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: 'Volatilitas Ekstrem',
        reasons: reasons,
      );
    }

    if (adx < minAdx) {
      reasons.add(
        'ADX (Wilder) ${adx.toStringAsFixed(1)} (< ${minAdx.toStringAsFixed(0)}): momentum tren jangka pendek masih lemah / sideways.',
      );
      return ScalpResult(
        timeframe: timeframe,
        signal: ScalpSignal.noEntry,
        currentPrice: currentPrice,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: 'Sideways / Momentum lemah',
        reasons: reasons,
      );
    }

    final isBullishTrend = ema50 > ema200 && currentPrice >= (ema50 - atr * 0.4);
    final isBearishTrend = ema50 < ema200 && currentPrice <= (ema50 + atr * 0.4);

    final nearDemand = demandLow != null &&
        demandHigh != null &&
        currentPrice >= (demandLow - atr * 0.45) &&
        currentPrice <= (demandHigh + atr * 0.65);
    final nearSupport = (currentPrice - nearestSupport).abs() <= atr * 0.85;

    final nearSupply = supplyLow != null &&
        supplyHigh != null &&
        currentPrice >= (supplyLow - atr * 0.65) &&
        currentPrice <= (supplyHigh + atr * 0.45);
    final nearResistance = (nearestResistance - currentPrice).abs() <= atr * 0.85;

    // --- KONDISI BUY JARAK DEKAT (RR 1:2) ---
    if (isBullishTrend && (nearDemand || nearSupport)) {
      reasons.add(
        'Tren naik jangka pendek selaras: EMA 50 (${ema50.toStringAsFixed(2)}) > EMA 200 (${ema200.toStringAsFixed(2)}).',
      );
      reasons.add(
        'ADX (Wilder) ${adx.toStringAsFixed(1)} (>= ${minAdx.toStringAsFixed(0)}): dorongan tren memadai.',
      );
      if (nearDemand) {
        reasons.add(
          'Harga berada di area Demand SnD (${demandLow!.toStringAsFixed(2)} - ${demandHigh!.toStringAsFixed(2)}).',
        );
      }
      if (nearSupport) {
        reasons.add(
          'Harga dekat area Support SNR (${nearestSupport.toStringAsFixed(2)}).',
        );
      }

      double sl = currentPrice - (atr * slMultiplier);
      if (nearSupport &&
          nearestSupport < currentPrice &&
          (currentPrice - nearestSupport) <= atr * 1.1) {
        sl = min(sl, nearestSupport - (atr * 0.25));
      }

      final slDistance = (currentPrice - sl).abs();
      final tp = currentPrice + (slDistance * 2.0);
      reasons.add(
        'Manajemen risiko RR 1:2 (SL ${slDistance.toStringAsFixed(2)} poin, TP ${(slDistance * 2.0).toStringAsFixed(2)} poin).',
      );

      return ScalpResult(
        timeframe: timeframe,
        signal: ScalpSignal.buy,
        currentPrice: currentPrice,
        stopLoss: sl,
        takeProfit: tp,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: nearDemand ? 'Area Demand (SnD)' : 'Area Support (SNR)',
        reasons: reasons,
      );
    }

    // --- KONDISI SELL JARAK DEKAT (RR 1:2) ---
    if (isBearishTrend && (nearSupply || nearResistance)) {
      reasons.add(
        'Tren turun jangka pendek selaras: EMA 50 (${ema50.toStringAsFixed(2)}) < EMA 200 (${ema200.toStringAsFixed(2)}).',
      );
      reasons.add(
        'ADX (Wilder) ${adx.toStringAsFixed(1)} (>= ${minAdx.toStringAsFixed(0)}): dorongan tren memadai.',
      );
      if (nearSupply) {
        reasons.add(
          'Harga berada di area Supply SnD (${supplyLow!.toStringAsFixed(2)} - ${supplyHigh!.toStringAsFixed(2)}).',
        );
      }
      if (nearResistance) {
        reasons.add(
          'Harga dekat area Resistance SNR (${nearestResistance.toStringAsFixed(2)}).',
        );
      }

      double sl = currentPrice + (atr * slMultiplier);
      if (nearResistance &&
          nearestResistance > currentPrice &&
          (nearestResistance - currentPrice) <= atr * 1.1) {
        sl = max(sl, nearestResistance + (atr * 0.25));
      }

      final slDistance = (sl - currentPrice).abs();
      final tp = currentPrice - (slDistance * 2.0);
      reasons.add(
        'Manajemen risiko RR 1:2 (SL ${slDistance.toStringAsFixed(2)} poin, TP ${(slDistance * 2.0).toStringAsFixed(2)} poin).',
      );

      return ScalpResult(
        timeframe: timeframe,
        signal: ScalpSignal.sell,
        currentPrice: currentPrice,
        stopLoss: sl,
        takeProfit: tp,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: nearSupply ? 'Area Supply (SnD)' : 'Area Resistance (SNR)',
        reasons: reasons,
      );
    }

    if (!isBullishTrend && !isBearishTrend) {
      reasons.add(
        'Struktur EMA 50 (${ema50.toStringAsFixed(2)}), EMA 200 (${ema200.toStringAsFixed(2)}), dan posisi harga belum selaras.',
      );
    } else {
      reasons.add(
        'Tren EMA & ADX (${adx.toStringAsFixed(1)}) sudah aktif, menunggu harga masuk area Support/Demand atau Resistance/Supply terdekat.',
      );
    }

    return ScalpResult(
      timeframe: timeframe,
      signal: ScalpSignal.noEntry,
      currentPrice: currentPrice,
      nearestSupport: nearestSupport,
      nearestResistance: nearestResistance,
      zoneInfo: 'Menunggu zona SNR/SnD & tren selaras',
      reasons: reasons,
    );
  }
}
