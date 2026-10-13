# Universal Converter

Universal Converter; PDF dosyalarını sunucuya göndermeden, tamamen cihaz üzerinde
DOCX biçimine dönüştüren bir Flutter masaüstü uygulamasıdır. Aynı Flutter kod tabanı
Windows, macOS ve Linux üzerinde çalışır. Dönüştürme motoru Python ile geliştirilmiş,
JSON Lines üzerinden haberleşen bağımsız bir worker sürecidir.

Son kullanıcı dağıtımlarında Python, pip veya proje kaynak kodu gerekmez. Python
worker her hedef işletim sisteminde PyInstaller ile bağımsız bir executable olarak
paketlenir ve Flutter uygulamasının içine yerleştirilir.

## Mimari

```text
Flutter UI
   └── ConverterEngine
         ├── DesktopPythonConverterEngine (Windows / macOS / Linux)
         └── UnsupportedConverterEngine (henüz desteklenmeyen platformlar)
                  │
                  │ JSON Lines: stdin / stdout
                  ▼
PyInstaller worker executable
   └── ConversionEngine
         └── PdfToDocxConverter (PyMuPDF + pdf2docx)
```

- HTTP, REST API, FastAPI, sunucu veya bulut servisi kullanılmaz.
- stdout yalnızca protokol mesajlarına ayrılmıştır; tanılama ve üçüncü taraf
  kütüphane çıktıları stderr üzerinden iletilir.
- Worker uygulama açıkken yaşamaya devam eder ve birden fazla isteği sırayla
  işleyebilir.
- UI, somut Python uygulamasına değil ortak `ConverterEngine` sözleşmesine bağlıdır.

## Debug ve release davranışı

Debug modunda motor şu sırayla aranır:

1. Flutter debug bundle içindeki PyInstaller worker
2. `backend/dist/debug/` altındaki worker
3. `.venv` veya PATH üzerindeki Python ile `backend.worker` kaynak modülü

Release modunda kaynak Python fallback'i kapalıdır. Uygulama yalnızca kendi bundle'ı
içindeki worker executable'ı çalıştırır. Böylece son kullanıcıdan Python kurulumu
istenmez ve eksik worker içeren bir release sessizce üretilmez.

Geliştirme sırasında aşağıdaki ortam değişkenleri kullanılabilir:

- `UNIVERSAL_CONVERTER_WORKER`: Hazır worker executable yolu
- `UNIVERSAL_CONVERTER_PYTHON`: Debug kaynak worker için Python yolu
- `UNIVERSAL_CONVERTER_PROJECT_ROOT`: Debug proje kökü

## Bundle yerleşimi

| Platform | Worker konumu |
| --- | --- |
| Windows | Uygulama executable'ının yanında `worker/universal_converter_worker.exe` |
| Linux | Flutter bundle kökünde `worker/universal_converter_worker` |
| macOS | `.app/Contents/Resources/worker/universal_converter_worker` |

Linux ve macOS paketleme adımları worker'a çalıştırma izni verir. Worker'ın çalışma
dizini kendi bulunduğu klasördür; giriş ve çıkış dosyaları mutlak yollarla protokole
aktarılır.

## Geliştirme ortamı

Gereksinimler:

- Flutter 3.38.9 / Dart 3.10.8 veya proje kısıtlarıyla uyumlu daha yeni sürüm
- 64-bit CPython 3.12 önerilir
- Hedef platformun Flutter masaüstü toolchain'i

Python ortamını hazırlayın:

```bash
python -m venv .venv
```

Windows PowerShell:

```powershell
.\.venv\Scripts\Activate.ps1
python -m pip install -r backend\requirements-dev.txt
flutter pub get
flutter run -d windows
```

macOS / Linux:

```bash
source .venv/bin/activate
python -m pip install -r backend/requirements-dev.txt
flutter pub get
flutter run -d macos   # veya: flutter run -d linux
```

Bu komutlar geliştiriciler içindir. Hazır dağıtımı kullanan kişiler Python veya pip
kurmaz.

## PyInstaller worker build'i

Build bağımlılıklarını yükleyin ve worker'ı hedef işletim sisteminin kendi üzerinde
oluşturun:

```bash
python -m pip install -r backend/requirements-build.txt
python tool/build_worker.py release
```

Debug worker için:

```bash
python tool/build_worker.py debug
```

Script:

- `backend/universal_converter_worker.spec` dosyasını kullanır.
- Windows'ta `.exe`, macOS/Linux'ta çalıştırılabilir dosya üretir.
- Sonucu `backend/dist/release/` veya `backend/dist/debug/` altına koyar.
- Üretilen executable'a gerçek stdin/stdout protokol smoke testi uygular.
- Platform, mimari ve Python sürümünü `manifest.json` içine yazar.

PyInstaller çıktıları taşınabilir değildir: Windows worker Windows'ta, macOS worker
macOS'ta, Linux worker Linux'ta üretilmelidir. CI bu nedenle her hedefi ayrı runner'da
derler.

## Yerel release üretimi

Worker her zaman Flutter release build'inden önce oluşturulmalıdır:

```bash
python tool/build_worker.py release
flutter build windows --release   # Windows
flutter build macos --release     # macOS
flutter build linux --release     # Linux
python tool/package_release.py
```

`package_release.py` bundle içindeki worker'ı yeniden smoke testten geçirir ve şu
dağıtımları üretir:

- Windows: taşınabilir ZIP
- macOS: `.app` içeren ZIP ve DMG
- Linux: taşınabilir `tar.gz`; `APPIMAGETOOL` ayarlıysa ayrıca AppImage

Çıktılar `dist/packages/` altında oluşur.

## GitHub Actions

[`.github/workflows/desktop-build.yml`](.github/workflows/desktop-build.yml) aşağıdaki
hedefleri birbirinden bağımsız olarak oluşturur:

- Windows x64 (`windows-latest`)
- Linux x64 (`ubuntu-22.04`)
- macOS Apple Silicon / arm64 (`macos-15`)
- macOS Intel / x64 (`macos-15-intel`)

Her job:

1. Python 3.12 ve Flutter 3.38.9 kurar.
2. Python testlerini çalıştırır.
3. `flutter analyze` ve `flutter test` çalıştırır.
4. PyInstaller worker'ı oluşturup test eder.
5. Flutter release uygulamasını worker ile birlikte derler.
6. Dağıtım paketini oluşturup GitHub Actions artifact'i olarak yükler.

Linux job'ı ayrıca sabitlenmiş `appimagetool` 1.9.1 ile AppImage üretmeyi dener.
Birincil Linux çıktısı her zaman `tar.gz` bundle'dır.

## macOS mimarileri, imzalama ve notarization

Intel ve Apple Silicon için ayrı worker ve `.app` artifact'leri üretilir. Bu yaklaşım,
PyInstaller içine giren Python, NumPy, OpenCV ve PyMuPDF native bileşenlerinin gerçek
hedef mimaride oluşturulmasını sağlar. Şu anda tek bir Universal 2 `.app` üretilmez;
iki mimari birleştirilmeden önce tüm nested native bağımlılıkların universal olması
ve her iki cihaz sınıfında test edilmesi gerekir.

Mevcut CI artifact'leri imzasız/ad-hoc geliştirme çıktılarıdır. Apple geliştirici
hesabı olmadan build alınabilir; ancak son kullanıcılara yayınlamadan önce Developer
ID ile imzalama ve notarization önerilir.

Önerilen yayın sırası:

1. `Developer ID Application` sertifikasını CI keychain'ine güvenli biçimde yükleyin.
2. Önce nested worker executable'ı hardened runtime ve timestamp ile imzalayın:

   ```bash
   codesign --force --options runtime --timestamp \
     --sign "Developer ID Application: Şirket Adı (TEAMID)" \
     convertforall_flutter.app/Contents/Resources/worker/universal_converter_worker
   ```

3. Xcode/Flutter uygulamasındaki framework ve executable'ları, ardından dış `.app`
   bundle'ını aynı kimlikle imzalayın. Nested kod dış bundle'dan önce imzalanmalıdır.
4. DMG oluşturun ve `notarytool` ile gönderin:

   ```bash
   xcrun notarytool submit UniversalConverter.dmg \
     --keychain-profile "universal-converter-notary" --wait
   xcrun stapler staple UniversalConverter.dmg
   ```

5. `codesign --verify --deep --strict --verbose=2`, `spctl --assess` ve temiz bir
   Mac üzerinde açılış/dönüşüm testi yapın.

Uygulama doğrudan dağıtım hedeflediği ve child worker'ın kullanıcının seçtiği dosyalara
erişmesi gerektiği için macOS App Sandbox etkin değildir. Mac App Store dağıtımı ayrı
bir sandbox/security-scoped erişim tasarımı gerektirir.

## Linux uyumluluğu

Linux binary uyumluluğu build alınan sistemin glibc ve native kütüphane tabanıyla
sınırlıdır. CI, tabanı gereksiz yere yükseltmemek için Ubuntu 22.04 kullanır. Bu,
bütün dağıtımlarda çalışma garantisi değildir:

- `tar.gz` hedef sistemde GTK 3 ve Flutter'ın gerekli sistem kütüphanelerini bekler.
- AppImage çıktısı kolay dağıtım sağlar fakat farklı dağıtımlarda ayrıca test
  edilmelidir; bazı sistemlerde FUSE kurulumu veya extract-and-run gerekebilir.
- Daha eski glibc hedefleri için worker ve Flutter bundle daha eski uyumlu bir build
  ortamında yeniden oluşturulmalıdır.
- Linux arm64 için mevcut workflow job'ı yoktur; uygun arm64 runner üzerinde aynı
  süreçle ayrı artifact üretilebilir.

## Python bağımlılık uyumluluğu

Runtime bağımlılıkları:

- `pdf2docx==0.5.8`
- `PyMuPDF>=1.24,<2`
- `pdf2docx` üzerinden gelen NumPy, OpenCV ve python-docx bileşenleri

CI her platform/mimaride bağımlılıkları kurar, testleri çalıştırır ve frozen worker'ı
başlatır. Bu, import ve temel dönüşüm uyumluluğunu kontrol eder. Yine de build almak;
farklı Windows sürümleri, gerçek Intel/Apple Silicon Mac'ler veya farklı Linux
dağıtımlarında kullanıcı testi yapılmış olduğu anlamına gelmez.

## Flutter–Python protokolü

Flutter her isteği stdin'e tek satırlık JSON olarak gönderir:

```json
{"id":"request-1","action":"convert","source_format":"pdf","target_format":"docx","input_path":"/files/source.pdf","output_path":"/files/result.docx","overwrite":false}
```

Worker aynı `id` değerine sahip tek satırlık JSON yanıtını stdout'a yazar:

```json
{
  "id": "request-1",
  "type": "conversion_result",
  "success": true,
  "input_path": "/files/source.pdf",
  "output_path": "/files/result.docx",
  "source_format": "pdf",
  "target_format": "docx",
  "duration_ms": 845,
  "message": "Conversion completed successfully.",
  "error": null
}
```

PDF modülü bozuk, boş veya parola korumalı girdileri reddeder. Dönüşüm hedef klasörde
geçici bir DOCX dosyasına yapılır ve yalnızca başarılı olduğunda atomik olarak son
adına taşınır. Kaynak PDF değiştirilmez.

## Testler

```bash
python -m pip install -r backend/requirements-dev.txt
python -m pytest backend/tests -q
flutter test
flutter analyze
```

Frozen worker testi için:

```bash
python -m pip install -r backend/requirements-build.txt
python tool/build_worker.py release
```

## Yeni dönüştürücü eklemek

1. `backend/converters/base.py` içindeki `Converter` sözleşmesini uygulayın.
2. Yeni modülü `backend/registry.py` içindeki kayıt listesine ekleyin.
3. Formatı Flutter `ConversionFormat` enum'una ve `supports()` kontrolüne ekleyin.
4. Doğrulama, gerçek çıktı ve frozen worker testlerini genişletin.

Yeni format eklenirken UI'nın veya JSON Lines taşıma katmanının yeniden yazılması
gerekmez.

## Önemli dosyalar

- `backend/worker.py`: JSON Lines worker protokolü
- `backend/universal_converter_worker.spec`: PyInstaller tanımı
- `tool/build_worker.py`: platforma özgü worker build ve smoke testi
- `tool/package_release.py`: ZIP, DMG, tar.gz ve AppImage paketleme
- `lib/services/desktop_python_converter_engine.dart`: ortak masaüstü adaptörü
- `windows/CMakeLists.txt`, `linux/CMakeLists.txt`: worker bundle kuralları
- `macos/Runner.xcodeproj/project.pbxproj`: macOS worker copy phase
- `.github/workflows/desktop-build.yml`: üç platformlu CI ve artifact akışı
