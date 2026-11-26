import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'analyzer_engine.dart';
import 'short_term_analyzer.dart';

void main() {
  runApp(const XauUsdApp());
}

class XauUsdApp extends StatelessWidget {
  const XauUsdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XAUUSD Smart Analyzer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F141A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF5B82E),
          secondary: Color(0xFF26A69A),
        ),
        cardColor: const Color(0xFF1A222C),
      ),
      home: const AnalyzerHomePage(),
    );
  }
}

class AnalyzerHomePage extends StatefulWidget {
  const AnalyzerHomePage({super.key});

  @override
  State<AnalyzerHomePage> createState() => _AnalyzerHomePageState();
}

class _AnalyzerHomePageState extends State<AnalyzerHomePage> {
  final TextEditingController _apiKeyController = TextEditingController();
  TradingMode _selectedMode = TradingMode.scalping;
  ScalpTimeframe? _selectedScalpTf;
  bool _isLoading = false;
  String? _errorMessage;
  AnalysisResult? _result;
  ScalpResult? _scalpResult;
  String _lastUpdated = '-';

  @override
  void initState() {
    super.initState();
    _loadSavedApiKey();
  }

  Future<void> _loadSavedApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('twelve_data_api_key') ?? '';
    setState(() {
      _apiKeyController.text = savedKey;
    });
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('twelve_data_api_key', key.trim());
  }

  String _formatNow() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  Future<List<Candle>> _fetchCandles({
    required String apiKey,
    required String interval,
  }) async {
    final uri = Uri.parse(
      'https://api.twelvedata.com/time_series?symbol=XAU/USD&interval=$interval&outputsize=220&apikey=$apiKey',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Gagal menghubungi server (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] == 'error') {
      throw Exception(data['message'] ?? 'Terjadi kesalahan API Twelve Data.');
    }

    final values = data['values'] as List<dynamic>?;
    if (values == null || values.length < 50) {
      throw Exception('Data candle tidak mencukupi untuk analisis.');
    }

    return values
        .map((item) => Candle.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  List<Candle> _chronologicalCandles(List<Candle> raw) {
    if (raw.length < 2) return raw;
    return raw.reversed.toList();
  }

  double _calculateEma(List<double> values, int period) {
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

  double _calculateAtr(List<Candle> candles, {int period = 14}) {
    if (candles.length < 2) return 0;
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

  double _calculateAdxWilder(List<Candle> candles, {int period = 14}) {
    if (candles.length <= period + 1) return 0;

    final List<double> plusDm = [];
    final List<double> minusDm = [];
    final List<double> trList = [];

    for (int i = 1; i < candles.length; i++) {
      final upMove = candles[i].high - candles[i - 1].high;
      final downMove = candles[i - 1].low - candles[i].low;

      plusDm.add((upMove > downMove && upMove > 0) ? upMove : 0);
      minusDm.add((downMove > upMove && downMove > 0) ? downMove : 0);

      final tr = max(
        candles[i].high - candles[i].low,
        max(
          (candles[i].high - candles[i - 1].close).abs(),
          (candles[i].low - candles[i - 1].close).abs(),
        ),
      );
      trList.add(tr);
    }

    double smoothTr = trList.sublist(0, period).reduce((a, b) => a + b);
    double smoothPlusDm = plusDm.sublist(0, period).reduce((a, b) => a + b);
    double smoothMinusDm = minusDm.sublist(0, period).reduce((a, b) => a + b);

    final List<double> dxList = [];
    for (int i = period; i < trList.length; i++) {
      smoothTr = smoothTr - (smoothTr / period) + trList[i];
      smoothPlusDm = smoothPlusDm - (smoothPlusDm / period) + plusDm[i];
      smoothMinusDm = smoothMinusDm - (smoothMinusDm / period) + minusDm[i];

      if (smoothTr == 0) continue;
      final plusDi = (smoothPlusDm / smoothTr) * 100;
      final minusDi = (smoothMinusDm / smoothTr) * 100;
      final diSum = plusDi + minusDi;
      if (diSum > 0) {
        dxList.add(((plusDi - minusDi).abs() / diSum) * 100);
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
    Future<void> _runAnalysis() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _errorMessage = 'Masukkan API Key Twelve Data terlebih dahulu.';
      });
      return;
    }

    await _saveApiKey(apiKey);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_selectedScalpTf != null) {
        final scalpTf = _selectedScalpTf!;
        final interval = scalpTf == ScalpTimeframe.m1 ? '1min' : '5min';
        final rawCandles = await _fetchCandles(apiKey: apiKey, interval: interval);
        final ordered = _chronologicalCandles(rawCandles);
        final closes = ordered.map((c) => c.close).toList();

        final currentPrice = ordered.last.close;
        final ema50 = _calculateEma(closes, 50);
        final ema200 = _calculateEma(closes, 200);
        final adx = _calculateAdxWilder(ordered, period: 14);
        final atr = _calculateAtr(ordered, period: 14);

        final scalpEval = ShortTermAnalyzer.evaluate(
          timeframe: scalpTf,
          currentPrice: currentPrice,
          ema50: ema50,
          ema200: ema200,
          adx: adx,
          atr: atr,
        );

        setState(() {
          _scalpResult = scalpEval;
          _result = null;
          _lastUpdated = _formatNow();
        });
        return;
      }

      final interval = _selectedMode == TradingMode.scalping ? '15min' : '1h';
      final candles = await _fetchCandles(apiKey: apiKey, interval: interval);

      final analysis = AnalyzerEngine.analyze(
        rawCandles: candles,
        mode: _selectedMode,
      );

      setState(() {
        _result = analysis;
        _scalpResult = null;
        _lastUpdated = _formatNow();
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _copyValue(String label, double value) {
    final formatted = value.toStringAsFixed(2);
    Clipboard.setData(ClipboardData(text: formatted));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label ($formatted) disalin ke clipboard'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Color _decisionColor(SignalDecision decision) {
    switch (decision) {
      case SignalDecision.buy:
        return const Color(0xFF22C55E);
      case SignalDecision.sell:
        return const Color(0xFFEF4444);
      case SignalDecision.noTrade:
        return const Color(0xFFF59E0B);
    }
  }

  Color _scalpDecisionColor(ScalpSignal signal) {
    switch (signal) {
      case ScalpSignal.buy:
        return const Color(0xFF22C55E);
      case ScalpSignal.sell:
        return const Color(0xFFEF4444);
      case ScalpSignal.noEntry:
        return const Color(0xFFF59E0B);
    }
  }

  String _scalpSignalLabel(ScalpSignal signal) {
    switch (signal) {
      case ScalpSignal.buy:
        return 'BUY';
      case ScalpSignal.sell:
        return 'SELL';
      case ScalpSignal.noEntry:
        return 'JANGAN ENTRY';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XAUUSD Smart Analyzer'),
        backgroundColor: const Color(0xFF151C24),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'API Key Twelve Data',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'Tempel API Key di sini...',
                        filled: true,
                        fillColor: const Color(0xFF11161D),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Pilih Gaya Trading',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Scalping (15m)')),
                            selected: _selectedScalpTf == null &&
                                _selectedMode == TradingMode.scalping,
                            selectedColor: const Color(0xFFF5B82E),
                            labelStyle: TextStyle(
                              color: (_selectedScalpTf == null &&
                                      _selectedMode == TradingMode.scalping)
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) {
                              setState(() {
                                _selectedScalpTf = null;
                                _selectedMode = TradingMode.scalping;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Hold (1H)')),
                            selected: _selectedScalpTf == null &&
                                _selectedMode == TradingMode.hold,
                            selectedColor: const Color(0xFFF5B82E),
                            labelStyle: TextStyle(
                              color: (_selectedScalpTf == null &&
                                      _selectedMode == TradingMode.hold)
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) {
                              setState(() {
                                _selectedScalpTf = null;
                                _selectedMode = TradingMode.hold;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('M1 (RR 1:2)')),
                            selected: _selectedScalpTf == ScalpTimeframe.m1,
                            selectedColor: const Color(0xFFF5B82E),
                            labelStyle: TextStyle(
                              color: _selectedScalpTf == ScalpTimeframe.m1
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) {
                              setState(() {
                                _selectedScalpTf = ScalpTimeframe.m1;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('M5 (RR 1:2)')),
                            selected: _selectedScalpTf == ScalpTimeframe.m5,
                            selectedColor: const Color(0xFFF5B82E),
                            labelStyle: TextStyle(
                              color: _selectedScalpTf == ScalpTimeframe.m5
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) {
                              setState(() {
                                _selectedScalpTf = ScalpTimeframe.m5;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5B82E),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isLoading ? null : _runAnalysis,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.analytics_outlined),
                        label: Text(
                          _isLoading ? 'Menganalisis Market...' : 'Analisis XAUUSD',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
                        if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],

            if (_scalpResult != null) ...[
              const SizedBox(height: 14),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _scalpDecisionColor(_scalpResult!.signal),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Update: $_lastUpdated • Jangka Pendek ${_scalpResult!.timeframe.name.toUpperCase()} (Target RR 1:2)',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _scalpSignalLabel(_scalpResult!.signal),
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: _scalpDecisionColor(_scalpResult!.signal),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Harga Saat Ini: ${_scalpResult!.currentPrice.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      if (_scalpResult!.signal != ScalpSignal.noEntry &&
                          _scalpResult!.stopLoss != null &&
                          _scalpResult!.takeProfit != null) ...[
                        const Divider(height: 24),
                        _priceTile('Entry', _scalpResult!.currentPrice),
                        _priceTile('Stop Loss (SL)', _scalpResult!.stopLoss!),
                        _priceTile('Take Profit (TP — RR 1:2)', _scalpResult!.takeProfit!),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        _scalpResult!.reason,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_result != null) ...[
              const SizedBox(height: 14),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _decisionColor(_result!.decision),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Update: $_lastUpdated • Zona: ${_result!.zoneInfo}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _result!.decisionLabel,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: _decisionColor(_result!.decision),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Harga Saat Ini: ${_result!.currentPrice.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      if (_result!.decision != SignalDecision.noTrade) ...[
                        const Divider(height: 24),
                        _priceTile('Entry', _result!.entryPrice!),
                        _priceTile('Stop Loss (SL)', _result!.stopLoss!),
                        _priceTile('Take Profit 1 (TP1)', _result!.tp1!),
                        _priceTile('Take Profit 2 (TP2)', _result!.tp2!),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Penjelasan Hasil Analisis',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      ..._result!.reasons.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(color: Color(0xFFF5B82E))),
                              Expanded(
                                child: Text(r, style: const TextStyle(height: 1.35)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 24),
                      const Text(
                        'Data Teknis (SNR / SND / Tren)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text('• Support / Demand Terdekat: ${_result!.nearestSupport.toStringAsFixed(2)}'),
                      Text('• Resistance / Supply Terdekat: ${_result!.nearestResistance.toStringAsFixed(2)}'),
                      Text('• EMA 50: ${_result!.ema50.toStringAsFixed(2)} | EMA 200: ${_result!.ema200.toStringAsFixed(2)}'),
                      Text('• ADX (Kekuatan Tren): ${_result!.adx.toStringAsFixed(1)} | ATR: ${_result!.atr.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _priceTile(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Row(
            children: [
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _copyValue(label, value),
                child: const Icon(Icons.copy, size: 18, color: Color(0xFFF5B82E)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
