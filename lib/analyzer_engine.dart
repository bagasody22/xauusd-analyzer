import 'dart:math';

enum TradingMode { scalping, hold }

enum SignalDecision { buy, sell, noTrade }

class Candle {
  final double open;
  final double high;
  final double low;
  final double close;

  Candle({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      open: double.parse(json['open'].toString()),
      high: double.parse(json['high'].toString()),
      low: double.parse(json['low'].toString()),
      close: double.parse(json['close'].toString()),
    );
  }
}

class AnalysisResult {
  final SignalDecision decision;
  final String decisionLabel;
  final double currentPrice;
  final double? entryPrice;
  final double? stopLoss;
  final double? tp1;
  final double? tp2;
  final double ema50;
  final double ema200;
  final double adx;
  final double atr;
  final double nearestSupport;
  final double nearestResistance;
  final String zoneInfo;
  final List<String> reasons;

  AnalysisResult({
    required this.decision,
    required this.decisionLabel,
    required this.currentPrice,
    required this.entryPrice,
    required this.stopLoss,
    required this.tp1,
    required this.tp2,
    required this.ema50,
    required this.ema200,
    required this.adx,
    required this.atr,
    required this.nearestSupport,
    required this.nearestResistance,
    required this.zoneInfo,
    required this.reasons,
  });
}

class AnalyzerEngine {
  static AnalysisResult analyze({
    required List<Candle> rawCandles,
    required TradingMode mode,
  }) {
    final candles = rawCandles.reversed.toList();
    final currentPrice = candles.last.close;
    final closes = candles.map((c) => c.close).toList();

    final ema50 = _calculateEma(closes, 50);
    final ema200 = _calculateEma(closes, 200);
    final atrSeries = _calculateAtrSeries(candles, 14);
    final atr = atrSeries.isNotEmpty ? atrSeries.last : 1.0;
    final avgAtr = atrSeries.isNotEmpty
        ? atrSeries.sublist(max(0, atrSeries.length - 20)).reduce((a, b) => a + b) /
            min(20, atrSeries.length)
        : atr;
    final adx = _calculateAdx(candles, 14);

    // Deteksi SNR (Swing High & Swing Low 25 candle terakhir)
    final window = candles.sublist(max(0, candles.length - 25));
    double swingHigh = window.first.high;
    double swingLow = window.first.low;
    for (final c in window) {
      if (c.high > swingHigh) swingHigh = c.high;
      if (c.low < swingLow) swingLow = c.low;
    }

    // Deteksi SND (Candle impulsif di 25 candle terakhir)
    double? demandLow;
    double? demandHigh;
    double? supplyLow;
    double? supplyHigh;

    for (int i = 1; i < window.length - 1; i++) {
      final prev = window[i - 1];
      final curr = window[i];
      final body = (curr.close - curr.open).abs();

      // Dorongan naik kuat -> area sebelum candle impulsif jadi Demand Zone
      if (curr.close > curr.open && body > avgAtr * 1.3) {
        demandLow = prev.low;
        demandHigh = max(prev.open, prev.close);
      }

      // Dorongan turun kuat -> area sebelum candle impulsif jadi Supply Zone
      if (curr.close < curr.open && body > avgAtr * 1.3) {
        supplyLow = min(prev.open, prev.close);
        supplyHigh = prev.high;
      }
    }

    final nearestSupport = demandLow != null ? min(swingLow, demandLow) : swingLow;
    final nearestResistance = supplyHigh != null ? max(swingHigh, supplyHigh) : swingHigh;

    final reasons = <String>[];

    // --- PRIORITAS 1: FILTER MARKET TIDAK KONDUSIF ---
    if (adx < 20) {
      reasons.add('ADX ${adx.toStringAsFixed(1)} (< 20): tren lemah / market sideways.');
      return _noTrade(
        currentPrice: currentPrice,
        ema50: ema50,
        ema200: ema200,
        adx: adx,
        atr: atr,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: 'Sideways / Tidak ada tren jelas',
        reasons: reasons,
      );
    }

    if (avgAtr > 0 && atr > avgAtr * 2.2) {
      reasons.add(
        'ATR ${atr.toStringAsFixed(2)} melonjak tajam dibanding rata-rata ${avgAtr.toStringAsFixed(2)} (rawan spike/whipsaw).',
      );
      return _noTrade(
        currentPrice: currentPrice,
        ema50: ema50,
        ema200: ema200,
        adx: adx,
        atr: atr,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: 'Volatilitas ekstrem',
        reasons: reasons,
      );
    }

    // --- PRIORITAS 2: ARAH TREN & ZONA SNR/SND ---
    final isBullishTrend = ema50 > ema200 && currentPrice >= ema200;
    final isBearishTrend = ema50 < ema200 && currentPrice <= ema200;

    final nearDemand = demandHigh != null &&
        demandLow != null &&
        currentPrice >= (demandLow - atr * 0.4) &&
        currentPrice <= (demandHigh + atr * 0.6);
    final nearSupport = (currentPrice - nearestSupport).abs() <= atr * 0.8;

    final nearSupply = supplyLow != null &&
        supplyHigh != null &&
        currentPrice >= (supplyLow - atr * 0.6) &&
        currentPrice <= (supplyHigh + atr * 0.4);
    final nearResistance = (nearestResistance - currentPrice).abs() <= atr * 0.8;

    final tp1Mult = mode == TradingMode.scalping ? 1.2 : 1.5;
    final tp2Mult = mode == TradingMode.scalping ? 2.2 : 3.5;

    // --- KONDISI BUY ---
    if (isBullishTrend && (nearDemand || nearSupport)) {
      reasons.add('Tren naik valid: EMA 50 > EMA 200 dan harga di atas EMA 200.');
      reasons.add('ADX ${adx.toStringAsFixed(1)} menunjukkan kekuatan tren memadai.');
      if (nearDemand) {
        reasons.add('Harga berada di area Demand Zone SND (${demandLow!.toStringAsFixed(2)} - ${demandHigh!.toStringAsFixed(2)}).');
      }
      if (nearSupport) {
        reasons.add('Harga dekat area Support SNR (${nearestSupport.toStringAsFixed(2)}).');
      }

      double sl = currentPrice - (atr * 1.5);
      if (nearSupport && nearestSupport < currentPrice) {
        sl = min(sl, nearestSupport - (atr * 0.3));
      }

      double tp1 = currentPrice + (atr * tp1Mult);
      double tp2 = currentPrice + (atr * tp2Mult);

      if (nearestResistance > currentPrice + (atr * 0.5)) {
        final safeCap = nearestResistance - (atr * 0.25);
        if (tp2 > safeCap) tp2 = max(tp1 + (atr * 0.4), safeCap);
      }

      return AnalysisResult(
        decision: SignalDecision.buy,
        decisionLabel: 'BUY',
        currentPrice: currentPrice,
        entryPrice: currentPrice,
        stopLoss: sl,
        tp1: tp1,
        tp2: tp2,
        ema50: ema50,
        ema200: ema200,
        adx: adx,
        atr: atr,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: nearDemand ? 'Area Demand (SND)' : 'Area Support (SNR)',
        reasons: reasons,
      );
    }

    // --- KONDISI SELL ---
    if (isBearishTrend && (nearSupply || nearResistance)) {
      reasons.add('Tren turun valid: EMA 50 < EMA 200 dan harga di bawah EMA 200.');
      reasons.add('ADX ${adx.toStringAsFixed(1)} menunjukkan kekuatan tren memadai.');
      if (nearSupply) {
        reasons.add('Harga berada di area Supply Zone SND (${supplyLow!.toStringAsFixed(2)} - ${supplyHigh!.toStringAsFixed(2)}).');
      }
      if (nearResistance) {
        reasons.add('Harga dekat area Resistance SNR (${nearestResistance.toStringAsFixed(2)}).');
      }

      double sl = currentPrice + (atr * 1.5);
      if (nearResistance && nearestResistance > currentPrice) {
        sl = max(sl, nearestResistance + (atr * 0.3));
      }

      double tp1 = currentPrice - (atr * tp1Mult);
      double tp2 = currentPrice - (atr * tp2Mult);

      if (nearestSupport < currentPrice - (atr * 0.5)) {
        final safeFloor = nearestSupport + (atr * 0.25);
        if (tp2 < safeFloor) tp2 = min(tp1 - (atr * 0.4), safeFloor);
      }

      return AnalysisResult(
        decision: SignalDecision.sell,
        decisionLabel: 'SELL',
        currentPrice: currentPrice,
        entryPrice: currentPrice,
        stopLoss: sl,
        tp1: tp1,
        tp2: tp2,
        ema50: ema50,
        ema200: ema200,
        adx: adx,
        atr: atr,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: nearSupply ? 'Area Supply (SND)' : 'Area Resistance (SNR)',
        reasons: reasons,
      );
    }

    // --- BELUM ADA KONFIRMASI ZONA & TREN ---
    if (!isBullishTrend && !isBearishTrend) {
      reasons.add('Posisi EMA 50, EMA 200, dan harga belum selaras untuk tren kuat.');
    } else {
      reasons.add('Harga belum menyentuh zona Support/Demand atau Resistance/Supply yang valid (posisi nanggung).');
    }

    return _noTrade(
      currentPrice: currentPrice,
      ema50: ema50,
      ema200: ema200,
      adx: adx,
      atr: atr,
      nearestSupport: nearestSupport,
      nearestResistance: nearestResistance,
      zoneInfo: 'Menunggu zona valid / tren selaras',
      reasons: reasons,
    );
  }

  static AnalysisResult _noTrade({
    required double currentPrice,
    required double ema50,
    required double ema200,
    required double adx,
    required double atr,
    required double nearestSupport,
    required double nearestResistance,
    required String zoneInfo,
    required List<String> reasons,
  }) {
    return AnalysisResult(
      decision: SignalDecision.noTrade,
      decisionLabel: 'JANGAN ENTRY',
      currentPrice: currentPrice,
      entryPrice: null,
      stopLoss: null,
      tp1: null,
      tp2: null,
      ema50: ema50,
      ema200: ema200,
      adx: adx,
      atr: atr,
      nearestSupport: nearestSupport,
      nearestResistance: nearestResistance,
      zoneInfo: zoneInfo,
      reasons: reasons,
    );
  }

  static double _calculateEma(List<double> values, int period) {
    if (values.isEmpty) return 0;
    final k = 2.0 / (period + 1);
    double ema = values.first;
    for (int i = 1; i < values.length; i++) {
      ema = (values[i] * k) + (ema * (1 - k));
    }
    return ema;
  }

  static List<double> _calculateAtrSeries(List<Candle> candles, int period) {
    if (candles.length < 2) return [];
    final trList = <double>[];
    for (int i = 1; i < candles.length; i++) {
      final curr = candles[i];
      final prevClose = candles[i - 1].close;
      final tr = max(
        curr.high - curr.low,
        max((curr.high - prevClose).abs(), (curr.low - prevClose).abs()),
      );
      trList.add(tr);
    }

    final atrList = <double>[];
    double sum = 0;
    for (int i = 0; i < trList.length; i++) {
      if (i < period) {
        sum += trList[i];
        if (i == period - 1) atrList.add(sum / period);
      } else {
        final nextAtr = ((atrList.last * (period - 1)) + trList[i]) / period;
        atrList.add(nextAtr);
      }
    }
    return atrList;
  }

  static double _calculateAdx(List<Candle> candles, int period) {
    if (candles.length < period + 2) return 25.0;
    final dxList = <double>[];

    for (int i = 1; i < candles.length; i++) {
      final curr = candles[i];
      final prev = candles[i - 1];

      final upMove = curr.high - prev.high;
      final downMove = prev.low - curr.low;

      final plusDm = (upMove > downMove && upMove > 0) ? upMove : 0.0;
      final minusDm = (downMove > upMove && downMove > 0) ? downMove : 0.0;

      final tr = max(
        curr.high - curr.low,
        max((curr.high - prev.close).abs(), (curr.low - prev.close).abs()),
      );

      if (tr > 0) {
        final plusDi = 100 * (plusDm / tr);
        final minusDi = 100 * (minusDm / tr);
        final sumDi = plusDi + minusDi;
        if (sumDi > 0) {
          dxList.add(100 * ((plusDi - minusDi).abs() / sumDi));
        }
      }
    }

    if (dxList.isEmpty) return 25.0;
    final recentDx = dxList.sublist(max(0, dxList.length - period));
    return recentDx.reduce((a, b) => a + b) / recentDx.length;
  }
}
