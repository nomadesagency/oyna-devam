# sleep

**TR:** Claude Code görevin sırasında kullanım limiti dolmaya yaklaşınca bilgisayarı uyutur, limit sıfırlanınca uyandırır ve görevi aynı oturumdan devam ettirir. macOS ve Windows için iki ayrı paket.

**EN:** While a Claude Code task runs, this puts the computer to sleep when the usage limit is nearly full, wakes it when the limit resets, and resumes the task in the same session. Two separate packages: macOS and Windows.

## İndirme / Download

Yeşil **Code** düğmesi → **Download ZIP** ile tüm repoyu indirebilir, sonra yalnızca kendi sisteminin klasörünü kullanabilirsin.

| Sistem | Klasör | Kılavuz (PDF, Türkçe) |
|---|---|---|
| macOS | [sleep-mac](sleep-mac) | [Sleep-Mac Kullanım Kılavuzu.pdf](sleep-mac/Sleep-Mac%20Kullan%C4%B1m%20K%C4%B1lavuzu.pdf) |
| Windows | [sleep-win](sleep-win) | [Sleep-Win Kullanım Kılavuzu.pdf](sleep-win/Sleep-Win%20Kullan%C4%B1m%20K%C4%B1lavuzu.pdf) |

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
