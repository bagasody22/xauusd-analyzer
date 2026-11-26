enum ScalpTimeframe { m1, m5 }

enum ScalpSignal { buy, sell, noEntry }

class ScalpResult {
  final ScalpTimeframe timeframe;
  final ScalpSignal signal;
  final double currentPrice;
  final double? stopLoss;
  final double? takeProfit;
  final double riskRewardRatio;
  final String reason;

  const ScalpResult({
    required this.timeframe,
    required this.signal,
    required this.currentPrice,
    this.stopLoss,
    this.takeProfit,
    this.riskRewardRatio = 2.0,
    required this.reason,
  });
}

class ShortTermAnalyzer {
  static ScalpResult evaluate({
    required ScalpTimeframe timeframe,
    required double currentPrice,
    required double ema50,
    required double ema200,
    required double adx,
    required double atr,
    double minAdx = 25.0,
    double slMultiplier = 1.2,
  }) {
    if (atr <= 0) {
      return ScalpResult(
        timeframe: timeframe,
        signal: ScalpSignal.noEntry,
        currentPrice: currentPrice,
        reason: 'ATR tidak valid; tahan entry untuk menjaga manajemen risiko.',
      );
    }

    final bool trendReady = adx >= minAdx;
    final bool bullish = trendReady && ema50 > ema200 && currentPrice > ema50;
    final bool bearish = trendReady && ema50 < ema200 && currentPrice < ema50;

    final double slDistance = atr * slMultiplier;
    final double tpDistance = slDistance * 2.0; // Target Risk:Reward 1:2

    if (bullish) {
      return ScalpResult(
        timeframe: timeframe,
        signal: ScalpSignal.buy,
        currentPrice: currentPrice,
        stopLoss: currentPrice - slDistance,
        takeProfit: currentPrice + tpDistance,
        reason: 'Tren naik jangka pendek selaras (RR 1:2).',
      );
    }

    if (bearish) {
      return ScalpResult(
        timeframe: timeframe,
        signal: ScalpSignal.sell,
        currentPrice: currentPrice,
        stopLoss: currentPrice + slDistance,
        takeProfit: currentPrice - tpDistance,
        reason: 'Tren turun jangka pendek selaras (RR 1:2).',
      );
    }

    return ScalpResult(
      timeframe: timeframe,
      signal: ScalpSignal.noEntry,
      currentPrice: currentPrice,
      reason: 'Kekuatan tren atau struktur EMA belum cukup selaras.',
    );
  }
}
