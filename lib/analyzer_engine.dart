import 'dart:math';

enum TradingMode { scalping, hold }

enum SignalDecision { buy, sell, noTrade }

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;

  Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      time: DateTime.parse(json['datetime'] as String),
      open: double.parse(json['open'] as String),
      high: double.parse(json['high'] as String),
      low: double.parse(json['low'] as String),
      close: double.parse(json['close'] as String),
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
    this.entryPrice,
    this.stopLoss,
    this.tp1,
    this.tp2,
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
  static double _calculateEMA(List<double> values, int period) {
    if (values.isEmpty) return 0;
    if (values.length < period) {
      return values.reduce((a, b) => a + b) / values.length;
    }
    final multiplier = 2.0 / (period + 1);
    double ema = values.sublist(0, period).reduce((a, b) => a + b) / period;
    for (int i = period; i < values.length; i++) {
      ema = ((values[i] - ema) * multiplier) + ema;
    }
    return ema;
  }

  static List<double> _calculateTR(List<Candle> candles) {
    final List<double> trList = [];
    for (int i = 1; i < candles.length; i++) {
      final high = candles[i].high;
      final low = candles[i].low;
      final prevClose = candles[i - 1].close;
      final tr = max(
        high - low,
        max((high - prevClose).abs(), (low - prevClose).abs()),
      );
      trList.add(tr);
    }
    return trList;
  }

  static double _calculateATR(List<Candle> candles, int period) {
    final trList = _calculateTR(candles);
    if (trList.isEmpty) return 0;
    if (trList.length < period) {
      return trList.reduce((a, b) => a + b) / trList.length;
    }
    double atr = trList.sublist(0, period).reduce((a, b) => a + b) / period;
    for (int i = period; i < trList.length; i++) {
      atr = ((atr * (period - 1)) + trList[i]) / period;
    }
    return atr;
  }

  static double _calculateADXWilder(List<Candle> candles, int period) {
    if (candles.length <= period + 1) return 0;

    final List<double> plusDM = [];
    final List<double> minusDM = [];
    final List<double> trList = [];

    for (int i = 1; i < candles.length; i++) {
      final upMove = candles[i].high - candles[i - 1].high;
      final downMove = candles[i - 1].low - candles[i].low;

      plusDM.add((upMove > downMove && upMove > 0) ? upMove : 0);
      minusDM.add((downMove > upMove && downMove > 0) ? downMove : 0);

      final tr = max(
        candles[i].high - candles[i].low,
        max(
          (candles[i].high - candles[i - 1].close).abs(),
          (candles[i].low - candles[i - 1].close).abs(),
        ),
      );
      trList.add(tr);
    }

    double smoothTR = trList.sublist(0, period).reduce((a, b) => a + b);
    double smoothPlusDM = plusDM.sublist(0, period).reduce((a, b) => a + b);
    double smoothMinusDM = minusDM.sublist(0, period).reduce((a, b) => a + b);

    final List<double> dxList = [];
    for (int i = period; i < trList.length; i++) {
      smoothTR = smoothTR - (smoothTR / period) + trList[i];
      smoothPlusDM = smoothPlusDM - (smoothPlusDM / period) + plusDM[i];
      smoothMinusDM = smoothMinusDM - (smoothMinusDM / period) + minusDM[i];

      if (smoothTR == 0) continue;
      final plusDI = (smoothPlusDM / smoothTR) * 100;
      final minusDI = (smoothMinusDM / smoothTR) * 100;
      final diSum = plusDI + minusDI;
      if (diSum > 0) {
        dxList.add(((plusDI - minusDI).abs() / diSum) * 100);
      }
    }

    if (dxList.isEmpty) return 0;
    if (dxList.length < period) {
      return dxList.reduce((a, b) => a + b) / dxList.length;
    }

    double adx = dxList.sublist(0, period).reduce((a, b) => a + b) / period;
    for (int i = period; i < dxList.length; i++) {
      adx = ((adx * (period - 1)) + dxList[i]) / period;
    }
    return adx;
  }
    static AnalysisResult analyze({
    required List<Candle> rawCandles,
    required TradingMode mode,
  }) {
    final candles = rawCandles.reversed.toList();
    final closes = candles.map((c) => c.close).toList();
    final currentPrice = closes.last;

    final ema50 = _calculateEMA(closes, 50);
    final ema200 = _calculateEMA(closes, 200);
    final adx = _calculateADXWilder(candles, 14);
    final atr = _calculateATR(candles, 14);

    // 1. Deteksi SNR (Swing High & Swing Low 25 candle terakhir)
    final snrWindow = candles.sublist(max(0, candles.length - 25));
    double swingHigh = snrWindow.first.high;
    double swingLow = snrWindow.first.low;
    for (final c in snrWindow) {
      if (c.high > swingHigh) swingHigh = c.high;
      if (c.low < swingLow) swingLow = c.low;
    }

    // 2. Deteksi SnD (Base candle sebelum gerakan impulsif kuat)
    double? demandLow;
    double? demandHigh;
    double? supplyLow;
    double? supplyHigh;

    final recentTr = _calculateTR(candles);
    final avgAtr = recentTr.isEmpty
        ? atr
        : recentTr.sublist(max(0, recentTr.length - 20)).reduce((a, b) => a + b) /
            min(20, recentTr.length);

    for (int i = max(1, candles.length - 25); i < candles.length - 1; i++) {
      final prev = candles[i - 1];
      final curr = candles[i];
      final body = (curr.close - curr.open).abs();

      if (curr.close > curr.open && body > avgAtr * 1.25) {
        demandLow = prev.low;
        demandHigh = max(prev.open, prev.close);
      }
      if (curr.close < curr.open && body > avgAtr * 1.25) {
        supplyLow = min(prev.open, prev.close);
        supplyHigh = prev.high;
      }
    }

    final nearestSupport =
        demandLow != null ? min(swingLow, demandLow) : swingLow;
    final nearestResistance =
        supplyHigh != null ? max(swingHigh, supplyHigh) : swingHigh;

    final reasons = <String>[];

    // 3. Filter Market Sideways atau Lonjakan Volatilitas Ekstrem
    if (adx < 20) {
      reasons.add(
        'ADX (Wilder) berada di ${adx.toStringAsFixed(1)} (< 20): pasar sedang sideways / tren lemah.',
      );
      return AnalysisResult(
        decision: SignalDecision.noTrade,
        decisionLabel: 'JANGAN ENTRY',
        currentPrice: currentPrice,
        ema50: ema50,
        ema200: ema200,
        adx: adx,
        atr: atr,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: 'Sideways / Konsolidasi',
        reasons: reasons,
      );
    }

    if (avgAtr > 0 && atr > avgAtr * 2.2) {
      reasons.add(
        'Volatilitas ekstrem terdeteksi (ATR ${atr.toStringAsFixed(2)}): risiko news/spike tinggi, hindari entry.',
      );
      return AnalysisResult(
        decision: SignalDecision.noTrade,
        decisionLabel: 'JANGAN ENTRY',
        currentPrice: currentPrice,
        ema50: ema50,
        ema200: ema200,
        adx: adx,
        atr: atr,
        nearestSupport: nearestSupport,
        nearestResistance: nearestResistance,
        zoneInfo: 'Volatilitas Tinggi (High Risk)',
        reasons: reasons,
      );
    }

    // 4. Evaluasi Tren EMA 50/200 (mengizinkan pullback wajar ke area zona)
    final isBullishTrend = ema50 > ema200 && currentPrice >= (ema200 - atr * 0.5);
    final isBearishTrend = ema50 < ema200 && currentPrice <= (ema200 + atr * 0.5);

    // 5. Pengaturan SL & TP1 (RR 1:2) berbeda antara M15 dan H1
    final slMult = mode == TradingMode.scalping ? 1.2 : 1.6;

    // --- CEK PELUANG BUY (RR 1:2) ---
    if (isBullishTrend) {
      final nearDemand = demandLow != null &&
          demandHigh != null &&
          currentPrice >= (demandLow - atr * 0.5) &&
          currentPrice <= (demandHigh + atr * 0.8);
      final nearSupport = (currentPrice - nearestSupport).abs() <= atr * 1.0;

      if (nearDemand || nearSupport) {
        reasons.add(
          'Tren naik valid: EMA 50 (${ema50.toStringAsFixed(2)}) > EMA 200 (${ema200.toStringAsFixed(2)}).',
        );
        reasons.add(
          'ADX (Wilder) ${adx.toStringAsFixed(1)} menunjukkan kekuatan tren memadai.',
        );
        if (nearDemand) {
          reasons.add(
            'Harga masuk zona Demand SnD (${demandLow!.toStringAsFixed(2)} - ${demandHigh!.toStringAsFixed(2)}).',
          );
        }
        if (nearSupport) {
          reasons.add(
            'Harga dekat area Support SNR (${nearestSupport.toStringAsFixed(2)}).',
          );
        }

        double sl = currentPrice - (atr * slMult);
        if (nearSupport &&
            nearestSupport < currentPrice &&
            (currentPrice - nearestSupport) <= atr * 1.3) {
          sl = min(sl, nearestSupport - (atr * 0.3));
        }

        final slDistance = (currentPrice - sl).abs();
        final tp1 = currentPrice + (slDistance * 2.0); // RR 1:2
        double tp2 = currentPrice + (slDistance * 3.0); // Ekstensi RR 1:3

        if (nearestResistance > tp1 && tp2 > nearestResistance) {
          tp2 = nearestResistance - (atr * 0.15);
        }

        reasons.add(
          'Target utama dikunci pada RR 1:2 (Risiko ${slDistance.toStringAsFixed(2)} poin, Target ${(slDistance * 2.0).toStringAsFixed(2)} poin).',
        );

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
          zoneInfo: nearDemand ? 'Area Demand (SnD)' : 'Area Support (SNR)',
          reasons: reasons,
        );
      }
    }

    // --- CEK PELUANG SELL (RR 1:2) ---
    if (isBearishTrend) {
      final nearSupply = supplyLow != null &&
          supplyHigh != null &&
          currentPrice >= (supplyLow - atr * 0.8) &&
          currentPrice <= (supplyHigh + atr * 0.5);
      final nearResistance =
          (nearestResistance - currentPrice).abs() <= atr * 1.0;

      if (nearSupply || nearResistance) {
        reasons.add(
          'Tren turun valid: EMA 50 (${ema50.toStringAsFixed(2)}) < EMA 200 (${ema200.toStringAsFixed(2)}).',
        );
        reasons.add(
          'ADX (Wilder) ${adx.toStringAsFixed(1)} menunjukkan kekuatan tren memadai.',
        );
        if (nearSupply) {
          reasons.add(
            'Harga masuk zona Supply SnD (${supplyLow!.toStringAsFixed(2)} - ${supplyHigh!.toStringAsFixed(2)}).',
          );
        }
        if (nearResistance) {
          reasons.add(
            'Harga dekat area Resistance SNR (${nearestResistance.toStringAsFixed(2)}).',
          );
        }

        double sl = currentPrice + (atr * slMult);
        if (nearResistance &&
            nearestResistance > currentPrice &&
            (nearestResistance - currentPrice) <= atr * 1.3) {
          sl = max(sl, nearestResistance + (atr * 0.3));
        }

        final slDistance = (sl - currentPrice).abs();
        final tp1 = currentPrice - (slDistance * 2.0); // RR 1:2
        double tp2 = currentPrice - (slDistance * 3.0); // Ekstensi RR 1:3

        if (nearestSupport < tp1 && tp2 < nearestSupport) {
          tp2 = nearestSupport + (atr * 0.15);
        }

        reasons.add(
          'Target utama dikunci pada RR 1:2 (Risiko ${slDistance.toStringAsFixed(2)} poin, Target ${(slDistance * 2.0).toStringAsFixed(2)} poin).',
        );

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
          zoneInfo: nearSupply ? 'Area Supply (SnD)' : 'Area Resistance (SNR)',
          reasons: reasons,
        );
      }
    }

    if (!isBullishTrend && !isBearishTrend) {
      reasons.add(
        'Posisi EMA 50, EMA 200, dan harga belum selaras untuk tren kuat.',
      );
    } else {
      reasons.add(
        'Tren EMA & ADX valid, namun harga belum masuk area Support/Demand atau Resistance/Supply.',
      );
    }

    return AnalysisResult(
      decision: SignalDecision.noTrade,
      decisionLabel: 'JANGAN ENTRY',
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
}
