# Weryfikacja Pamięci RAM przez magistralę AXI4 (Aldec BFM)

## Opis Projektu
Środowisko weryfikacyjne dla sprzętowego modułu pamięci `taxi_axi_ram`. Architektura wykorzystuje magistralę AXI4 do przesyłu danych obrazu (zapis i odczyt za pomocą transakcji typu BURST). Weryfikacja jest wspierana przez model weryfikacyjny (BFM) Aldec. Projekt integruje zautomatyzowane skrypty w języku Python przetwarzające pliki graficzne na wsady hexadecymalne (format zgodny z Verilog `$readmemh`), aby weryfikować poprawność transferu na realistycznych danych pikseli.

## Architektura
*   **`taxi_axi_ram.sv`**: Docelowy moduł pamięci połączony ze standardowym interfejsem AXI4 Slave. Obejmuje kontrolę faz zapisu, odczytu i response.
*   **`axi4_master.sv`**: Wrapper sprzętowy instancjonujący chroniony rdzeń `Ax_Axi4MasterBFM` dostarczony przez Aldec. Implementuje zadania (tasks) do obsługi transferów AXI4 `INCR`.
*   **`taxi_axi_if.sv`**: Zunifikowany interfejs SystemVerilog przenoszący wszystkie kanały AXI (AW, W, B, AR, R) ze zdefiniowanymi modportami dla mastera i slave'a.
*   **`img_ram_tb.sv`**: Główny testbench sterujący przebiegiem testu. Odpowiada za załadowanie obrazu do magistrali, nadzór weryfikacji "w locie" z użyciem backdoor access (sprawdzanie zawartości wewnętrznej pamięci `mem`) oraz zrzut danych wyjściowych.

## Struktura Katalogów
*   `src/` – Kod źródłowy (interfejsy, RTL, środowisko testowe).
*   `python/` – Skrypty do konwersji i obróbki formatów: `png2hex.py`, `hex2png.py`.
*   `photos/` – Referencyjne oraz wygenerowane pliki `.png`.

## Flow Symulacyjny
Przepływ automatyzuje skrypt `run.do` (TCL), który po kolei realizuje:
1.  **Generacja Wsadu**: Wywołanie `png2hex.py`, które konwertuje `obrazek.png` do płaskiego pliku tekstowego `image.hex` oraz automatycznie mapuje szerokość adresu (`ADDR_W`) na podstawie rozmiarów.
2.  **Kompilacja i Mapowanie**: Zbudowanie bibliotek Aldec BFM oraz kompilacja kodu RTL (interfejs -> target -> master BFM -> TB).
3.  **Transakcje i Weryfikacja**:
    *   Testbench symuluje burst zapisu przesyłający wsad `image.hex` po magistrali AXI4 do struktury RAM.
    *   Kontrola ścieżki zapisu wewnątrz pamięci.
    *   Testbench symuluje burst odczytu z adresów i weryfikuje pełną zgodność wyjściowych danych z wejściowymi.
    *   Wynik wyrzucany jest jako `image_out.hex` za pośrednictwem funkcji `$writememh`.
4.  **Rekonstrukcja Obrazu**: Ostateczne wywołanie `hex2png.py` w celu wygenerowania gotowego obrazu ze zweryfikowanego zrzutu z szyny danych.

## Debugowanie
*   **Zgodność danych na szynie**: Jakiekolwiek przesunięcia na szynie zgłaszane są bezpośrednio do konsoli symulatora przez system makr `$error` z informacją o indeksie błędnego transferu (niezgodność `read_back` vs `img_data`).