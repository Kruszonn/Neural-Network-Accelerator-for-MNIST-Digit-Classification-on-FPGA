Rozpoznawanie cyfr na FPGA: sprzętowy akcelerator sieci neuronowej

Płytka: Digilent Nexys A7-100T (układ AMD/Xilinx Artix-7)
Języki i narzędzia: VHDL-2008, Python (numpy), Vivado 2026, GHDL
Status: projekt w realizacji. Wyniki poniżej pochodzą z symulacji; synteza i test na płytce są w toku.

Układ FPGA rozpoznaje ręcznie pisane cyfry (0–9). Komputer wysyła obrazek cyfry przez kabel USB, płytka oblicza, jaka to cyfra, pokazuje wynik na wyświetlaczu i odsyła go do komputera.

Obliczenia wykonuje własny, zaprojektowany od zera układ cyfrowy. Nie ma tu procesora ani gotowych bloków IP.

 Komputer (Python)                         Płytka FPGA (VHDL)
┌─────────────────┐   obrazek 28x28   ┌──────────────────────────────┐
│ wysyła obrazek  │ ────────────────► │ sieć neuronowa w sprzęcie    │
│ sprawdza wynik  │ ◄──────────────── │ wynik → wyświetlacz + LED    │
└─────────────────┘   cyfra + dane    └──────────────────────────────┘
1. Training	Python	Mała sieć neuronowa (MLP 784 → 64 → 10) uczy się na zbiorze MNIST (70 000 obrazków cyfr).
2. Quantization	Python	Wagi sieci zamieniane są z ułamków na 8-bitowe liczby całkowite (int8), które FPGA liczy szybko i tanio.
3. Eksport	Python	Wagi (ok. 50 KB) zapisywane są do plików, które Vivado wpisuje do pamięci BRAM układu.
4. Inference	FPGA	Blok MAC (mnożenie + dodawanie) w każdym takcie zegara przetwarza jeden piksel. Na końcu blok argmax wybiera cyfrę z najwyższym wynikiem.
5. Komunikacja	FPGA ↔ PC	Obrazek przychodzi przez UART, a wynik wraca tą samą drogą i pojawia się na wyświetlaczu 7-segmentowym.

Wyniki (symulacja)
Parametr	Wynik
Skuteczność sieci (float, przed kwantyzacją)	97,51% na 10 000 obrazków testowych
Skuteczność sieci (int8, tak jak w sprzęcie)	97,55%, czyli kwantyzacja nie pogorszyła wyniku
Czas rozpoznania jednej cyfry	ok. 508 µs (50 826 taktów zegara 100 MHz)
Zgodność sprzętu z modelem w Pythonie	100%: wszystkie testy zgodne bit po bicie
Rozmiar wag	ok. 50 KB, czyli ok. 8% pamięci BRAM układu
Jak sprawdzana jest poprawność?

W Pythonie powstał golden model, czyli wzorcowy model, który liczy dokładnie to samo co sprzęt, na tych samych liczbach całkowitych. Automatyczne testbenche w symulatorze GHDL podają te same obrazki do układu VHDL i porównują każdą liczbę wyniku z modelem. Jeśli choć jeden bit się różni, test kończy się błędem.

Struktura projektu
python/        trening sieci, kwantyzacja, eksport wag, program do komunikacji z płytką
rtl/           kod VHDL układu (pamięci, blok MAC, sieć, UART, wyświetlacz)
sim/           testbenche i skrypt uruchamiający symulację
constraints/   przypisanie pinów płytki Nexys A7
scripts/       skrypty Tcl do automatycznego zbudowania projektu w Vivado
mem/           wytrenowane wagi sieci
docs/          szczegółowa dokumentacja te
