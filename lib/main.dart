import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:audioplayers/audioplayers.dart';

import 'data.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final primaryDisplay = await screenRetriever.getPrimaryDisplay();
  final screenSize = primaryDisplay.size;

  WindowOptions windowOptions = WindowOptions(
    size: screenSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setIgnoreMouseEvents(true);
    await windowManager.hide();
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with TrayListener {
  bool _mostrarFoxy = false;
  bool _modoConfiguracao = false;

  int _intervaloSegundos = 1;
  int _chanceUmaEm = 800;

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _timerPrincipal;
  Timer? _timerEsconder;

  final TextEditingController _tempoController = TextEditingController();
  final TextEditingController _chanceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _tempoController.text = _intervaloSegundos.toString();
    _chanceController.text = _chanceUmaEm.toString();

    _configurarSystemTray();
    _iniciarTemporizadorSusto();
  }

  Future<void> _configurarSystemTray() async {
    try {
      // Detecta o diretório onde o .exe está rodando
      final String exePath = Platform.resolvedExecutable;
      final String exeDir = Directory(exePath).parent.path;

      // Tenta obter o ícone que o Flutter copia para a pasta de dados/recursos no build
      String iconPath = '$exeDir/data/flutter_assets/assets/app_icon.ico';

      if (!File(iconPath).existsSync()) {
        // Fallback para ambiente local de desenvolvimento (debug via VS Code)
        iconPath =
            '${Directory.current.path}\\windows\\runner\\resources\\app_icon.ico';
      }

      await trayManager.setIcon(iconPath);
    } catch (e) {
      debugPrint('Erro ao carregar ícone da tray: $e');
    }

    Menu menu = Menu(
      items: [
        MenuItem(key: 'abrir_config', label: 'Abrir Configurações'),
        MenuItem(key: 'testar_susto', label: 'Testar Susto Agora'),
        MenuItem.separator(),
        MenuItem(key: 'fechar_app', label: 'Sair do Programa'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    _abrirPainelConfiguracoes();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'abrir_config') {
      _abrirPainelConfiguracoes();
    } else if (menuItem.key == 'testar_susto') {
      _dispararSusto();
    } else if (menuItem.key == 'fechar_app') {
      exit(0);
    }
  }

  /// Ativa a interface de configurações no centro da tela sem redimensionar a janela do SO
  Future<void> _abrirPainelConfiguracoes() async {
    setState(() {
      _modoConfiguracao = true;
    });

    await windowManager.setIgnoreMouseEvents(false);
    await windowManager.show();
    await windowManager.focus();
  }

  /// Desativa as configurações e oculta a janela novamente
  Future<void> _salvarEOcultar() async {
    setState(() {
      _intervaloSegundos = int.tryParse(_tempoController.text) ?? 1;
      _chanceUmaEm = int.tryParse(_chanceController.text) ?? 800;
      _modoConfiguracao = false;
    });

    _iniciarTemporizadorSusto();

    await windowManager.setIgnoreMouseEvents(true);
    await windowManager.hide();
  }

  void _iniciarTemporizadorSusto() {
    _timerPrincipal?.cancel();
    _timerPrincipal = Timer.periodic(Duration(seconds: _intervaloSegundos), (
      timer,
    ) async {
      if (_modoConfiguracao) return;

      var sorteio = Random().nextInt(_chanceUmaEm);
      if (sorteio == 87 % _chanceUmaEm) {
        _dispararSusto();
      }
    });
  }

  Future<void> _dispararSusto() async {
    if (!mounted) return;

    // 1. Atualiza a árvore do Flutter primeiro
    setState(() {
      _mostrarFoxy = true;
    });

    // 2. Exibe a janela nativa em tela cheia se estiver oculta
    if (!_modoConfiguracao) {
      await windowManager.setIgnoreMouseEvents(true);
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
    }

    // 3. Executa o áudio
    try {
      final bytesSom = base64Decode(myData.somBase64);
      await _audioPlayer.play(BytesSource(bytesSom));
    } catch (e) {
      debugPrint('Erro ao tocar som: $e');
    }

    // 4. Esconde após 1 segundo
    _timerEsconder?.cancel();
    _timerEsconder = Timer(const Duration(seconds: 1), () async {
      if (!mounted) return;

      setState(() {
        _mostrarFoxy = false;
      });

      if (!_modoConfiguracao) {
        await windowManager.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: _modoConfiguracao
            ? Colors.black54
            : const Color(0x01111111),
        body: Stack(
          children: [
            // Camada 1: Painel de configurações
            if (_modoConfiguracao) _buildPainelUI(),

            // Camada 2: O susto (fica por cima de tudo sempre que _mostrarFoxy for true)
            if (_mostrarFoxy) _buildSustoUI(),
          ],
        ),
      ),
    );
  }

  /// Painel de Configurações estilo Modal Flutuante
  Widget _buildPainelUI() {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Configurações do Jumpscare',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _tempoController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Intervalo (Segundos)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _chanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Chance (1 em N)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _dispararSusto,
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: const Text(
                  'Testar Susto Agora',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 255, 145, 0),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _salvarEOcultar,
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'Salvar e Ocultar',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 54, 141, 58),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => exit(0),
                icon: const Icon(
                  Icons.power_settings_new,
                  color: Color.fromARGB(255, 245, 27, 27),
                ),
                label: const Text(
                  'Fechar Programa',
                  style: TextStyle(color: Color.fromARGB(255, 245, 27, 27)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renderização do Susto em Tela Cheia
  Widget _buildSustoUI() {
    return _mostrarFoxy
        ? SizedBox.expand(
            child: Center(
              child: Image.memory(
                base64Decode(myData.gifBase64),
                gaplessPlayback: true,
                fit: BoxFit.contain,
                cacheWidth: null,
                cacheHeight: null,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          )
        : const SizedBox.shrink();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    _timerPrincipal?.cancel();
    _timerEsconder?.cancel();
    _audioPlayer.dispose();
    _tempoController.dispose();
    _chanceController.dispose();
    super.dispose();
  }
}
