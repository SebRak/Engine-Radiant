RAWFRONT RADIANT PREVIEW 0.1 — RC01 / PACZKA WEWNĘTRZNA

1. Rozpakuj całe archiwum do katalogu z prawem zapisu. Obecna baza
   NetRadiant-Custom wymaga ścieżki ASCII, np. C:\Games\RawFront-Radiant.
   Spacje są dozwolone.
2. Uruchom Start_RawFront_Radiant.cmd. Pierwsze uruchomienie korzysta z
   internetu. Launcher pobiera oficjalne RawFront Tools. Tools pobiera
   zgodny build gry 0.10-preview.1 i generuje profil, tekstury narzędziowe
   oraz definicje encji. Ten tryb startowy nie pobiera prywatnego repozytorium
   rawfront-content i nie udostępnia pełnego zestawu materiałów i modeli.
3. Nowe mapy zapisuj pod rawfront-workspace\editor\rawfront\maps.
   Nazwa mapy powinna mieć małe litery ASCII, cyfry lub podkreślenia.
   Umieść marker Spawn > General i użyj przycisku Play.

To wewnętrzna paczka weryfikacyjna. Jej plik radiant.exe pochodzi z buildu
Context Menu 01. Wymaga podmiany na build RC01 po kompilacji poprawki C++.
Sześć definicji Actor jest obecnych, ale pakiet nie dostarcza ich modeli.
Podstawowy start testuje konfigurację. Pełny test mapowania wymaga również
autoryzowanego źródła materiałów i modeli edytora.
Jeżeli Windows oznaczył skrypty jako pochodzące z Internetu, zweryfikuj
źródło i SHA-256 archiwum, zanim zdecydujesz o jego odblokowaniu.

ŹRÓDŁA I LICENCJE

NetRadiant-Custom 68ecbed64b7be78741878c730279b5471d978c7c:
https://github.com/Garux/netradiant-custom
Patche użyte do kompilacji:
https://github.com/SebRak/Engine-Radiant/tree/605468ae0df928ececc9c8e979f2869ebe72d085/patches
W katalogu licenses są dokumenty GPL, LGPL i wykaz licencji upstream.

Repozytorium pełnych zasobów (dostęp kontrolowany przez właściciela):
https://github.com/rutkowski-tomasz/rawfront-content/tree/c1a7d37617069ad1b2a6cb734728482101d98e3c
Warunki poszczególnych zasobów znajdują się w content/ASSETS.md.
RawFront Tools: https://get.rawfront.com/get/tools-windows-x64.zip
Archiwum zawiera edytor, Qt i skrypty konfiguracji. RawFront Tools i build
gry są pobierane do katalogu paczki.
