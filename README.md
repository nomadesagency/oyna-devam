# Oyna Devam

**TR:** Claude Code ile uzun bir görevi kullanım limitlerine takılmadan sürdür. Limit dolmaya yaklaşınca görev bekletilir (bilgisayar uyutulur), limit sıfırlanınca bilgisayar uyandırılır ve görev aynı oturumdan kaldığı yerden devam eder. macOS ve Windows için iki ayrı paket.

**EN:** Run long Claude Code tasks without being stopped by usage limits. When the limit is nearly full the task is held (the computer is suspended); when the limit resets the computer wakes and the task continues in the same session. Two separate packages: macOS and Windows.

## İndirme / Download

Yeşil **Code** düğmesi → **Download ZIP** ile tüm repoyu indirebilir, sonra yalnızca kendi sisteminin klasörünü kullanabilirsin.

| Sistem | Klasör | Kılavuz (PDF, Türkçe) |
|---|---|---|
| macOS | [oyna-devam-mac](oyna-devam-mac) | [Oyna Devam - Mac Kullanım Kılavuzu.pdf](oyna-devam-mac/Oyna%20Devam%20-%20Mac%20Kullan%C4%B1m%20K%C4%B1lavuzu.pdf) |
| Windows | [oyna-devam-win](oyna-devam-win) | [Oyna Devam - Windows Kullanım Kılavuzu.pdf](oyna-devam-win/Oyna%20Devam%20-%20Windows%20Kullan%C4%B1m%20K%C4%B1lavuzu.pdf) |

Kurulum için kılavuzu oku; kısaca: klasörü bilgisayarına kopyala, Mac'te `install.command`, Windows'ta `install.bat` dosyasına çift tıkla. Yeni sürüm çıktığında klasörü yenisiyle değiştirip kurulumu yeniden çalıştırman yeterlidir.

## Önce oku

- Bu yazılım "olduğu gibi" sunulur, garanti yoktur. Ayrıntı: `NOTICE.txt`.
- Kurulum, `~/.claude/settings.json` dosyana hook ekler (önce yedek alınır) ve görev sürerken Claude Code'un her işlem için onay istememesini sağlayabilir. Yalnız güvendiğin görevlerde ve klasörlerde kullan, önce küçük bir görevle dene.
- Her şey istediğin an kaldırılabilir (`uninstall`).
- Windows sürümü yenidir ve gerçek Windows bilgisayarlarda henüz yaygın denenmemiştir.
- Bağımsız bir projedir. Anthropic ile bağlantısı, onayı ya da desteği yoktur. "Claude" ve "Claude Code" Anthropic, PBC'nin ticari markalarıdır.

## Lisans

Betikler ve metin dosyaları [MIT](LICENSE) lisanslıdır. Kılavuzlardaki logo ve slogan ile gömülü yazı tipi (Space Grotesk, SIL OFL 1.1) bu lisansın dışındadır.

## İletişim

Issues kapalıdır. [nomadesagency.com](https://nomadesagency.com)
