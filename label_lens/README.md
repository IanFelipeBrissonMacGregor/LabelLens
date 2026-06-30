# NutriScan

App em Flutter para escanear o código de barras de produtos alimentícios e exibir a tabela nutricional, índice de saudabilidade e alérgenos — com destaque visual por cores.

## O que o app faz

1. Abre a câmera em uma tela de scanner com visor animado.
2. Ao capturar, lê o código de barras (EAN-13) com `google_mlkit_barcode_scanning`.
3. Busca o produto na API pública do [Open Food Facts](https://world.openfoodfacts.org).
4. Exibe uma tela de resultado com:
    - Nome do produto e índice nutricional (anel animado, 0–100).
    - Alérgenos, separados em **"Contém"** (vermelho) e **"Pode conter traços"** (laranja).
    - Tabela nutricional completa (calorias, carboidratos, proteínas, gorduras, fibras, sódio, açúcares) com barra de progresso e % do valor diário.
    - Informações de porção da embalagem.

## Sistema de cores dos alérgenos

O destaque de alérgenos funciona em duas camadas:

**Nível de severidade (bloco)**
| Bloco | Cor | Significado |
|---|---|---|
| CONTÉM | Vermelho `#EF4444` | Alérgeno confirmado no produto (`allergens_tags` da API) |
| PODE CONTER TRAÇOS | Laranja `#FFB347` | Risco de contaminação cruzada (`traces_tags` da API) |

**Nível de alérgeno (chip individual)**

Cada alérgeno tem ícone e cor próprios, definidos em `_allergenMap`:

| Alérgeno | Cor |
|---|---|
| Leite | Azul `#60A5FA` |
| Ovos | Amarelo `#FBBF24` |
| Glúten / Trigo | Laranja `#F97316` |
| Amendoim / Oleaginosas | Vermelho `#EF4444` |
| Soja | Verde-limão `#84CC16` |
| Peixe | Ciano `#22D3EE` |
| Crustáceos / Moluscos | Vermelho `#FF6B6B` |
| Salsão | Verde `#4ADE80` |
| Mostarda / Gergelim | Amarelo |
| Sulfitos | Roxo `#A78BFA` |
| Tremoço | Laranja `#FB923C` |

Se um alérgeno não estiver no mapa, ele simplesmente não aparece (a seção inteira só é exibida se houver pelo menos um item reconhecido).

## Estrutura do código

Tudo está em um único arquivo, `main.dart`, dividido em:

- `ScannerScreen` — câmera, captura, leitura de código de barras e chamada à API.
- `ProductResultScreen` — parsing dos dados do produto e toda a UI de resultado.
- `_AllergenMeta`, `_NutrientRow` — classes auxiliares de dados.
- `_CornerPainter`, `_RingPainter` — desenhos customizados (cantos do visor e anel de score).

## Tratamento de erros

- **Câmera sem permissão ou indisponível**: mostra uma tela de erro com botão "Tentar novamente", em vez de travar em loading infinito.
- **Código de barras não detectado**: `SnackBar` pedindo para tentar de novo.
- **Produto não encontrado na base**: `SnackBar` informando.
- **Falha de rede**: `SnackBar` de erro, sem quebrar o app.
- **Campos nutricionais ausentes ou em formato inesperado** (`null`, `String` em vez de `num`): tratados via `_toNum()`, `_fmt()` e `_pct()`, sempre com fallback (`-` ou `0`) em vez de crashar.

## Dependências (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.10.5+9
  google_mlkit_barcode_scanning: ^0.14.2
  http: ^1.2.0
```

> Versão verificada no pub.dev em 30/06/2026. Confirme sempre a mais recente antes de rodar `flutter pub get`, pois pacotes mudam com frequência.

## Configuração nativa necessária

### Android (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

E em `android/app/build.gradle`, o `google_mlkit_barcode_scanning` 0.14.2 exige:

```gradle
minSdkVersion 21
targetSdkVersion 35
compileSdkVersion 35
```

### iOS (`ios/Runner/Info.plist` e `ios/Podfile`)

```xml
<key>NSCameraUsageDescription</key>
<string>Precisamos da câmera para escanear o código de barras dos produtos.</string>
```

Sem essa chave, o app **encerra abruptamente** ao tentar abrir a câmera no iOS — não retorna erro tratável, então é essencial incluir antes de rodar em dispositivo real.

O MLKit também exige `IPHONEOS_DEPLOYMENT_TARGET` mínimo de **15.5** no `Podfile`, e exclusão da arquitetura `armv7` (ML Kit não suporta 32-bit). Veja o guia oficial em [pub.dev/packages/google_mlkit_barcode_scanning](https://pub.dev/packages/google_mlkit_barcode_scanning) na seção "Requirements" para o trecho exato do `Podfile`.

## Como rodar

```bash
flutter pub get
flutter run
```

## Limitações conhecidas

- Só lê código de barras no formato **EAN-13** (o mais comum em produtos brasileiros/europeus). Para suportar outros formatos (UPC-A, EAN-8, etc.), adicione-os na lista `formats` do `BarcodeScanner`.
- O índice nutricional (0–100) é calculado a partir do `nutriscore_score` da API quando disponível; quando ausente, usa um valor neutro (50) como fallback.
- Depende inteiramente da base de dados do Open Food Facts — produtos não cadastrados lá não serão encontrados.