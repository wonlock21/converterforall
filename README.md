# Universal Converter

Universal Converter, dosyaları bir sunucuya göndermeden cihaz üzerinde dönüştürmeyi
amaçlayan bir Flutter masaüstü uygulamasıdır. İlk sürüm Windows üzerinde **PDF →
DOCX** dönüşümünü destekler. Flutter arayüzü ile platforma özgü dönüştürme motoru
birbirinden ayrıdır; Android, Linux ve macOS için daha sonra ayrı motorlar eklenebilir.

## Mimari

```text
Flutter UI
   └── ConverterEngine (ortak Dart sözleşmesi)
         ├── WindowsPythonConverterEngine → yerel Python worker
         └── UnsupportedConverterEngine   → gelecekteki platform adaptörleri

Python worker (JSON Lines / stdin-stdout)
   └── ConversionEngine (doğrulama + kayıt defteri)
         └── PdfToDocxConverter (PyMuPDF + pdf2docx)
```

Flutter, Python motorunu `dart:io` içindeki `Process` API'si ile arka planda başlatır.
Worker uygulama açıkken yaşayabilir ve birden fazla dönüşüm isteğini aynı süreçte
işleyebilir. Kullanıcının terminal veya komut satırı kullanması gerekmez.
HTTP, REST API, FastAPI, sunucu veya bulut servisi yoktur. İlk bağımlılık kurulumu
internet gerektirebilir; dönüşüm işlemi daha sonra tamamen çevrimdışı çalışır.

## Gereksinimler

- Flutter SDK (proje Dart SDK `^3.10.8` kullanır)
- Windows 10 veya üzeri
- 64-bit CPython 3.10 veya üzeri (bu sürüm CPython 3.14 ile test edilmiştir)
- Python paketlerini kurmak için `pip`

> PyMuPDF ve OpenCV gibi paketlerin hazır Windows wheel dosyalarını kullanabilmek
> için python.org üzerinden kurulan standart 64-bit CPython önerilir. MSYS2 Python
> ortamları kaynak derlemesi gerektirebilir.

## Kurulum

PowerShell'de proje kökünde:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt
flutter pub get
flutter run -d windows
```

Uygulama varsayılan olarak önce `.venv\Scripts\python.exe` dosyasını, ardından
PATH içindeki `python` komutunu arar. Farklı bir yorumlayıcı kullanılacaksa:

```powershell
$env:UNIVERSAL_CONVERTER_PYTHON = 'C:\Python312\python.exe'
flutter run -d windows
```

Proje kökü çalışma dizininden bulunamazsa
`UNIVERSAL_CONVERTER_PROJECT_ROOT` ortam değişkeni ayarlanabilir. Bağımsız EXE
paketleme bu sürümün kapsamında değildir; geliştirme ortamında `backend/` klasörü
uygulama ile birlikte bulunmalıdır.

## Kullanım

1. **PDF seç** ile kaynak dosyayı seçin.
2. Çıktı formatı olarak DOCX'i seçin.
3. **Klasör seç** ile hedef klasörü belirleyin. Çıktı adı kaynak dosya adıyla aynı,
   uzantısı `.docx` olur.
4. Gerekirse açıkça “üzerine yaz” seçeneğini işaretleyin.
5. **Dönüştürmeyi başlat** düğmesine basın.

İşlem ayrı bir Python sürecinde asenkron çalıştığı için Flutter arayüzü bloke olmaz.

## Flutter–Python iletişimi

`backend.worker` yalnızca Flutter tarafından `python -m backend.worker` ile arka
planda başlatılır. Flutter her dönüşüm isteğini
stdin'e tek satırlık JSON olarak gönderir:

```json
{"id":"request-1","action":"convert","source_format":"pdf","target_format":"docx","input_path":"C:\\files\\source.pdf","output_path":"C:\\files\\result.docx","overwrite":false}
```

Worker aynı `id` değerine sahip tek satırlık yapılandırılmış bir JSON yanıtını
stdout'a yazar:

```json
{
  "id": "request-1",
  "type": "conversion_result",
  "success": true,
  "input_path": "C:\\files\\source.pdf",
  "output_path": "C:\\files\\result.docx",
  "source_format": "pdf",
  "target_format": "docx",
  "duration_ms": 845,
  "message": "Conversion completed successfully.",
  "error": null
}
```

Stdout yalnızca protokol mesajlarına ayrılmıştır. `pdf2docx` ilerleme çıktıları,
Python logları ve tanılama bilgileri stderr'e yönlendirilir. Bozuk JSON, eksik alan,
desteklenmeyen işlem ve motor hataları da yapılandırılmış hata yanıtı üretir. Flutter
yanıtları istek kimliğiyle eşleştirir; süreç kapanırsa bekleyen işlemler kullanıcıya
gösterilebilen bir `ConverterEngineException` ile tamamlanır.

Ortak motor giriş/çıkış uzantılarını, dosya ve klasörlerin varlığını, hedefin
yazılabilirliğini ve üzerine yazma iznini doğrular. PDF modülü dosyayı PyMuPDF ile
açarak bozuk, boş veya parola korumalı girdileri reddeder. Dönüşüm aynı hedef
klasörde geçici bir DOCX dosyasına yapılır; başarılı ve boş olmayan çıktı atomik
olarak son adına taşınır. Kaynak dosyaya yazılmaz ve hem PyMuPDF belgeleri hem de
`pdf2docx.Converter` güvenli şekilde kapatılır.

## Yeni dönüştürücü eklemek

Python tarafında:

1. `backend/converters/base.py` içindeki `Converter` sözleşmesini uygulayan ayrı bir
   modül oluşturun.
2. `source_format`, `target_format`, `validate_input()` ve `convert()` üyelerini
   tanımlayın.
3. Dönüştürücüyü `backend/registry.py` içindeki `create_default_engine()` listesine
   ekleyin.
4. Doğrulama, hata, kaynak kapatma ve gerçek çıktı testlerini ekleyin.

Flutter tarafında formatı `ConversionFormat` enum'una ekleyin ve ilgili platform
adaptörünün `supports()`/protokol alanı eşlemesini genişletin. Yeni bir platform motoru
eklendiğinde `ConverterEngine` uygulanmalı ve `platform_converter_engine.dart`
içindeki seçim fabrikasına bağlanmalıdır. UI, somut Python sınıfına bağımlı değildir.

## Testler

Python testleri:

```powershell
python -m pip install -r backend\requirements-dev.txt
python -m pytest backend\tests -q
```

Test paketi ortak doğrulamaları, yapılandırılmış worker protokol hatalarını, stdout ve
stderr ayrımını, üzerine yazma
davranışını ve gerçek bir PDF'nin DOCX'e dönüşmesini kapsar. Gerçek dönüşüm testi
geçici bir PDF üretir, kaynak dosyanın hash değerinin değişmediğini ve çıktı içinde
`word/document.xml` bulunduğunu doğrular.

Flutter test ve analizleri:

```powershell
flutter test
flutter analyze
```

## Önemli dosyalar

- `backend/engine.py`: ortak doğrulama ve dönüştürme orkestrasyonu
- `backend/converters/base.py`: Python dönüştürücü sözleşmesi
- `backend/converters/pdf_to_docx.py`: gerçek PDF → DOCX uygulaması
- `backend/worker.py`: JSON stdin/stdout süreç protokolü
- `backend/tests/`: birim ve gerçek dönüşüm testleri
- `lib/services/converter_engine.dart`: platformdan bağımsız Flutter sözleşmesi
- `lib/services/windows_python_converter_engine.dart`: Windows/Python adaptörü
- `lib/features/converter/converter_page.dart`: dosya seçimi ve işlem durumu UI'ı

## Mevcut kapsam

Yalnızca Windows üzerinde PDF → DOCX dönüşümü uygulanmıştır. Android, Linux ve
macOS motorları ile Windows bağımsız EXE paketleme sonraki aşamalara bırakılmıştır.
