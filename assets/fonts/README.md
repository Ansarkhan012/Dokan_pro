# Bundled fonts

Both fonts are licensed under the **SIL Open Font License 1.1** (no Reserved
Font Name is declared). They ship unmodified, together with their `OFL.txt`,
and the licences are registered with Flutter's `LicenseRegistry` at startup,
so they appear on the app's licences page.

| Family (pubspec) | Files | Source (official Noto release) | Release archive SHA-256 |
| --- | --- | --- | --- |
| `NotoNastaliqUrdu` | `noto_nastaliq_urdu/NotoNastaliqUrdu-{Regular,Bold}.ttf` (hinted) | https://github.com/notofonts/nastaliq/releases/tag/NotoNastaliqUrdu-v4.000 | `0725a7a9dfd450961b18227445cc9a5d21624d68b1f88fa52e4c6a0fe7576728` |
| `NotoNaskhArabic` | `noto_naskh_arabic/NotoNaskhArabic-{Regular,Bold}.ttf` (hinted) | https://github.com/notofonts/arabic/releases/tag/NotoNaskhArabic-v2.021 | `6c050ab9bd087d69b733c505a7576e60c528c2f33cd7b91005a5bd7da4514032` (matches GitHub's published digest) |

File SHA-256:

```
4d05b6821862ca1f3c80c47c80a352b47dd349ab73814f60e377eea311e0e42c  noto_nastaliq_urdu/NotoNastaliqUrdu-Regular.ttf
7c9e53eb934043adda6a5da5d993fa61d64dd1123d5227c4b63a5b36ae46ab77  noto_nastaliq_urdu/NotoNastaliqUrdu-Bold.ttf
ba3bdc1a53ed88874f32302b720523980d4351e9dd10de0395af1e7f7a18faa3  noto_nastaliq_urdu/OFL.txt
6f0a92031367b2f5a2078fe9d24f3433122b61a0bad57c423aad8f3c39aa2e6e  noto_naskh_arabic/NotoNaskhArabic-Regular.ttf
04017b0ccdd1156dcde3bc386734c1b03165261762f16a025c8afc9088ae76e9  noto_naskh_arabic/NotoNaskhArabic-Bold.ttf
a7a5a25eb188bf1cd96982030d53e23c33485c69b1044a562254226857ee13af  noto_naskh_arabic/OFL.txt
```

Usage: the fonts are only a fallback for Urdu (Arabic-script) glyphs while
the UI language is Urdu. Latin text and the Western digits 0-9 keep the
default font, so amounts look identical in both languages. The owner can
compare Nastaliq and Naskh from the language menu (Stage 2 font spike).
