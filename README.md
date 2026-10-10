# Ultimo chilometro – versione digitale (uso personale)

Adattamento in Godot 4.3 di una corsa ciclistica a carte, costruito sulle scansioni
delle tessere della propria copia fisica. Solo per uso personale: la grafica delle
tessere appartiene ai rispettivi autori ed editori.

## Avvio
Apri la cartella con Godot (testato con 4.3 e 4.7: Importa → project.godot) e premi Esegui.
All'avvio compare la copertina (`assets/copertina.webp`, e `copertina_avvio.png` per il
caricamento di Godot); un clic, un tocco o un tasto portano al menu.

## Icona dell'app
Viene dalla copertina, in tre formati in `assets/`:
- `icona.png`: icona del progetto e della finestra;
- `icona.icns`: Mac, con margine e angoli arrotondati nello stile macOS;
- `icona.ico`: Windows, dalla 16×16 alla 256×256.

Sono impostate nel progetto (Application → Config), quindi le esportazioni per Mac, Windows e
Android le usano senza altre impostazioni. Per iOS va indicata nelle opzioni d'esportazione.

## Comandi della telecamera
- Trascina col tasto sinistro: ruota la vista.
- Trascina col destro o col centrale, oppure Maiusc + sinistro: sposta la vista.
- Rotellina o pinch sul trackpad: zoom.
- **Segui**: la vista accompagna il corridore attivo. Se sposti la vista a mano si
  disattiva e resta disattivato finché non lo riaccendi.
- **Tutto**: inquadra l'intero percorso.

## Gioco online
Si gioca a distanza con il proprio progetto Firebase (Realtime Database, piano gratuito). Ognuno
apre il gioco (anche dal sito su GitHub Pages) e in cima al menu sceglie **Partita → Online**.

- **Chi crea la stanza** imposta squadre e percorso come al solito: le squadre su *Giocatore*
  diventano i posti per gli amici (la prima è la sua). Preme *Crea una stanza* e comunica il
  codice di 4 lettere. Quando ci sono tutti preme *Inizia la corsa*: i posti rimasti liberi li
  gioca il computer.
- **Gli amici** scrivono il nome e il codice e premono *Entra*.
- A ogni turno ognuno sceglie le sue carte; quando sono arrivate quelle di tutti, ogni dispositivo
  risolve il turno da sé. La partita è identica ovunque perché tutti usano lo stesso seme casuale
  e ogni mazzo si rimescola con un suo generatore: sul database passano solo le carte scelte. Le
  squadre del computer le gioca il dispositivo di chi ha creato la stanza.
- In questa prima versione online: corsa singola (niente tour né fuga), schieramento casuale.
- A ogni turno ogni dispositivo pubblica anche un'impronta dello stato: se due corse non
  coincidono più (per esempio con versioni diverse del gioco) la cronaca lo segnala.

**Configurazione Firebase.** La configurazione pubblica del progetto è in `scripts/net.gd`.
Le regole di sicurezza sono in `firebase/database.rules.json` e vanno pubblicate nella console
(Realtime Database → Regole). In Authentication va attivato l'accesso *Anonimo*. Le regole
permettono di leggere una stanza solo a chi ne conosce il codice, di configurarla e cancellarla
solo a chi l'ha creata, e a ogni giocatore di scrivere una volta sola, a ogni turno, le carte
della propria squadra.

**Prove senza Firebase.** `tests/firebase_mock.py` è un finto Firebase locale. Con
`FR_DB_URL`, `FR_AUTH_URL` e `FR_REFRESH_URL` che puntano lì, `tests/net_test.gd` prova il
collegamento e le regole, `tests/online_ui.gd` gioca una corsa intera tra due istanze del gioco
(host e ospite) e `tests/lockstep.gd` controlla senza rete che due dispositivi restino allineati.

## Squadre
- Da 1 a 6 squadre: Rossi, Blu, Verdi, Neri, Rosa, Bianchi. Con più di 10 corridori
  serve la partenza di Peloton (faccia 1 o 1B).
- Ogni squadra può essere guidata da un **giocatore**, dal **computer**, oppure essere
  una delle squadre automatiche di Peloton:
  - **Squadra Peloton** (al massimo una): ha solo il mazzo del rouleur con due carte
    Attacco!, e muove entrambi i corridori con la stessa carta. Con Attacco! il
    corridore davanti fa 2 e quello dietro 9.
  - **Squadra Muscle**: ha i due mazzi, con una carta Muscolo (5) nel mazzo del sprinteur,
    e gira la prima carta di ciascuno.
  - Le squadre automatiche non prendono mai carte fatica e si schierano per prime.
- **Fatica iniziale**: carte fatica in più per le squadre di giocatori, come handicap
  o per il solitario (il regolamento ne consiglia 3, con una Squadra Peloton e una Muscle).
- **Schieramento a scelta**: come da regolamento, ogni squadra a turno piazza i suoi
  corridori dietro la linea di partenza toccando i dischi gialli. Altrimenti è casuale.

## Ciclisti
I modelli 3D vengono da Meshy, ridotti a 14 mila triangoli ciascuno, e sono in
`assets/models/`:
- `passista.glb` (rouleur): seduto dritto, con berretto e tubolare a tracolla.
- `velocista.glb` (sprinteur): basso e lanciato sul manubrio.

La maglia prende il colore della squadra con lo shader `jersey.gdshader`. La
maschera `*_mask.png` indica quali punti della texture sono maglia: i grigi sul busto,
esclusa la bici. Ogni ciclista sta su una basetta ovale del colore della squadra, con
la lettera P o V stampata ai due lati e sempre dritta rispetto allo schermo.

## Velocità delle animazioni
L'impostazione **Animazioni** (Lenta, Normale, Veloce; la predefinita è Lenta) regola quanto
tempo impiega un corridore a percorrere ogni casella: 0,4 s, 0,22 s o 0,12 s. Vale per i
movimenti, per la scia e per il replay. Si sceglie nel menu iniziale e si cambia anche in gara
dal menu in alto nel pannello.

## Pedalata
- **Ruote**: i modelli sono divisi in corpo e due ruote (`corpo`, `ruota_0`, `ruota_1` nei
  file .glb), con il perno al mozzo. Le ruote girano in proporzione allo spazio percorso.
- **Gambe**: le muove lo shader (`assets/models/jersey.gdshader`). I punti delle gambe
  descrivono un cerchio attorno ai pedali, con le due gambe in opposizione, ampiezza piena ai
  piedi e nulla all'anca. Il telaio, al centro della bici, resta fermo.
- **Parametri**: posizione dei pedali, raggio delle ruote e altezza dell'anca sono in
  `assets/models/pedalata.json`.
- **Movimento**: cadenza e rotazione seguono lo spostamento reale del segnalino (2,6 giri di
  ruota per giro di pedivella). Chi va più veloce pedala più veloce, da fermi tutto si ferma,
  in discesa le gambe restano immobili (ruota libera). Vale anche nel replay.

## Carte e plance
Le carte e le plance vengono dalle scansioni della tua copia, in `assets/carte/`:
- `s_<squadra>.webp` e `r_<squadra>.webp`: la carta energia dello sprinteur e del rouleur
  di ogni colore. Il valore stampato è stato cancellato e il gioco riscrive negli angoli
  quello della carta, nel colore della squadra.
- `s_fatica.webp` e `r_fatica.webp`: le carte fatica (sempre 2).
- `retro_s.webp` e `retro_r.webp`: i retri.
- `plancia_<squadra>.png`: la plancia di ogni colore, con lo sprinteur a sinistra e il
  rouleur a destra. Nel pannello mostra mazzo, riciclo e fatica di ciascun corridore e
  mette in evidenza quello per cui stai scegliendo.

## Scelta della carta
Passando il mouse su una carta, in pista si accende la casella d'arrivo del corridore, con un
disco giallo pulsante nella corsia in cui finirebbe e piccoli segni sulle caselle attraversate.
Il disco diventa arancione se la casella voluta è piena e il corridore si fermerebbe prima.
È una stima fatta con le posizioni attuali: gli altri corridori si muovono nello stesso turno.

## Fine della tappa, resoconto e replay
- La tappa continua finché tutti i corridori hanno tagliato il traguardo. Chi arriva
  esce dalla pista, così le caselle dopo la linea restano libere per gli altri.
- **Resoconto** a schermo intero: in alto l'ordine d'arrivo (turno, tempo, distacco) e la
  classifica a squadre (somma dei due corridori); nel tour, sotto, la classifica generale dei
  corridori e delle squadre. In fondo: "Rivedi la tappa", "Tappa successiva" e
  "Torna al menu".
- **Torna al menu** (anche dal piccolo pulsante "Menu" in alto nel pannello di gara) riporta
  alla scelta della corsa con le impostazioni di prima. Se la corsa o il tour non sono
  finiti, chiede conferma.
  - Tempo: un minuto per turno, meno 10" per ogni casella oltre la linea, con 10" di
    abbuono ai primi due arrivati. È la sintesi delle regole del Grand Tour fatta dalla
    comunità; il regolamento ufficiale del Grand Tour non è incluso.
- **Replay**: rivede la tappa come un'unica animazione continua, senza pause tra un
  turno e l'altro. In ogni turno tutti i corridori si muovono insieme, scia compresa, e
  impiegano lo stesso tempo per andare dalla casella di partenza a quella d'arrivo,
  quindi chi ha giocato una carta più alta va più veloce. Chi taglia il traguardo esce di
  scena mentre gli altri proseguono. Si può mettere in pausa, cambiare velocità
  (×0,5 … ×4) e ricominciare.

## Tessere del Grand Tour
Si attivano nel menu alla voce "Grand Tour". Le immagini vengono da foto, non da scansioni:
sono state raddrizzate (prospettiva) e portate alla scala delle altre tessere, 253,5 pixel
per casella.

- **Arrivo largo v/V**: sostituisce u/U, anche nei percorsi del libretto e nei tour.
  - v: in pianura, 1 casella prima della linea e 5 dopo, a tre corsie;
  - V: tutte e 6 le caselle in salita, 2 prima della linea e 4 dopo, a tre corsie.
- **Curva stretta z/Z**: un tornante a U di 6 caselle (due a due corsie, tre a una corsia sul
  bagnato, una a due corsie). Nei percorsi casuali può comparire al posto di un rettilineo.
  - chi chiude il movimento su una casella bagnata dopo aver perso almeno una casella per
    strada chiusa cade, e resta a terra nella sua corsia;
  - una casella con tutte le corsie occupate da corridori a terra non si attraversa: chi
    arriva si ferma prima, e se anche quella casella è bagnata cade a sua volta;
  - niente scia da o verso una casella con un corridore a terra;
  - al turno dopo il corridore si rialza e la sua carta vale 2 in meno (con un 2 si rialza
    soltanto).
- **Rotonde x/X e y/Y**: tre caselle a due corsie, poi la strada si divide in una corsia
  interna da 3 caselle e una esterna da 5, che si ricongiungono all'uscita. X e Y escono a
  destra, x e y a sinistra. Nei percorsi casuali possono comparire con l'opzione Grand Tour.
  - si deve muovere esattamente quanto la carta, preferendo la corsia interna; se non si può,
    si prende la corsia che fa avanzare di più; una volta su una corsia non si cambia;
  - ordine di movimento: prima chi è sulle corsie separate (il più vicino all'uscita, a parità
    l'interna), poi chi è sul tratto a due corsie;
  - scia: chi è sull'ultima casella a due corsie la riceve da entrambe le corsie (prima si
    risolve l'interna); tra le due corsie separate non c'è né scia né riparo dalla fatica.
  Nel motore il percorso è un grafo: ogni casella conosce le successive, e la scia si calcola
  su ciascuno dei percorsi possibili.
- **Argini delle tessere irregolari** (tornante e rotonde): seguono il contorno vero della
  tessera, ricavato dalla trasparenza dell'immagine.
- **Tappe del Grand Tour (versione TTS)**: le 21 tappe ricostruite dal modulo di Tabletop
  Simulator, nei gruppi "Grand Tour TTS (5–6 giocatori)" e "(2–4 giocatori)", anche come tour.
  La 1 è a cronometro a squadre, la 10 individuale, la 5, la 15 e la 20 sono lunghe (con il
  ristoro). Non sono le carte ufficiali: le tappe con l'asterisco hanno il finale ricomposto.
  Il dettaglio è in `docs/grand-tour-tts-tappe.md`.
- **Tappe del Grand Tour dal regolamento**: nel gruppo "Grand Tour" ci sono le tappe 3 e 4, le
  uniche leggibili per intero nel regolamento. Si possono giocare anche come tour. Con
  "Sequenza" si scrivono percorsi con v/V, z/Z, x/X e y/Y.

## Tappe speciali del Grand Tour
Si scelgono nel menu, alla voce "Tipo di tappa". Con "Normale", le tappe del libretto che nel
Tour 2018 erano a cronometro lo restano: Cholet (a squadre) ed Espelette (individuale).
- **Cronometro a squadre**:
  - tutti partono dalla casella subito dietro la linea, e più squadre possono condividerla
    (in pista sono sfalsate);
  - ogni squadra corre come se fosse sola: le altre non contano per movimento, scia e fatica;
  - entrambi i corridori prendono il tempo del più lento, e c'è al massimo un podio a squadra.
- **Cronometro individuale**: stessa partenza, nessuna scia (nemmeno dal compagno); a ogni
  turno la fatica va al rouleur e allo sprinteur che hanno giocato la carta più alta (a
  parità, a tutti).
- **Nelle cronometro**: niente gettoni sprint e montagna, niente fuga.
- **Tappa lunga**: quattro rettilinei da 6 caselle in più, presi tra le tessere non usate
  (meglio i rifornimenti di Peloton) e inseriti a metà percorso. Il gettone del ristoro sta
  sulla prima casella di un rettilineo a metà tappa. Il primo che lo raggiunge lo prende, e a
  fine turno ogni corridore recupera carte giocate fino a 24 punti (25 per chi ha il gettone),
  scegliendo la combinazione di valore più alto; poi tutto il mazzo si rimescola.

## Meteo
Si attiva nel menu ("Meteo"). A ogni tappa il gioco distribuisce a caso 13 gettoni (4
condizioni e 9 di bel tempo), uno per ogni rettilineo esclusi partenza e arrivo. Accanto al
rettilineo compare la sagoma corrispondente (`assets/meteo/`), e la cronaca annuncia il meteo
della tappa. Sopra il rettilineo ci sono effetti animati: nuvole e pioggia con schizzi e asfalto
lucido per il bagnato; folate di vento e foglie che corrono nel senso di marcia (a favore),
contro (contrario) o di traverso (laterale). Gli effetti valgono per tutte e sei le caselle del rettilineo:
- **Vento laterale**: niente scia, né data né ricevuta.
- **Vento a favore**: chi inizia il turno lì pesca 5 carte.
- **Vento contrario**: chi inizia il turno lì pesca 3 carte.
- **Bagnato**: chi si ferma lì dopo aver perso caselle per strada chiusa cade (stesse regole
  della curva stretta del Grand Tour). Al turno dopo ci si rialza con 2 in meno, applicati
  dopo gli aggiustamenti di discesa e rifornimento; in salita resta il limite di 5. Con un 2
  ci si rialza soltanto e si va nella corsia destra, se libera.

## Variante Breakaway (Peloton)
Si attiva nel menu ("Fuga"). La tessera 2 diventa la seconda del percorso: lato chiaro con
5–6 squadre, lato scuro con 1–4. Nei percorsi del libretto viene inserita al secondo posto.

Dopo lo schieramento si tiene l'asta:
- ogni squadra (non quelle automatiche) sceglie un corridore e fa due offerte, ognuna
  pescando 4 carte e giocandone una;
- va in fuga la somma più alta, uno o due corridori secondo il numero di squadre, sulla
  zona tratteggiata; a parità vince il più arretrato;
- chi va in fuga perde le carte giocate e prende 2 carte fatica, gli altri riciclano le
  offerte, poi tutti rimescolano.

## CPU
Nel menu, alla voce **Computer**, si sceglie il livello delle squadre guidate dal computer.

- **Normale**: valuta ogni carta sulla posizione di adesso (avanzamento, economia del mazzo,
  fatica da scaricare, salite, scia, distanza dalla testa della corsa).
- **Difficile** ed **Esperto**: per ogni carta in mano immaginano molti finali di corsa, fino
  al traguardo (Monte Carlo), e scelgono quella che in media porta al miglior piazzamento della
  squadra. Nei finali immaginati:
  - le carte degli altri si pescano a caso tra quelle che hanno davvero ancora, perché l'ordine
    dei mazzi è sconosciuto;
  - gli altri corridori giocano con una versione rapida della CPU normale;
  - le carte nettamente peggiori vengono scartate dopo pochi finali.
  Difficile immagina 16 finali per carta (al massimo 0,7 s per decisione), Esperto 32 (1,5 s).
  Sul browser i tempi sono più lunghi e la CPU si ferma al limite di tempo.
- Il computer sceglie le sue carte prima dei giocatori, così non può conoscere le loro.

In corse simulate a 4 squadre (due per tipo), la CPU Difficile vince il 70% delle corse contro
la Normale. La prova si ripete con
`godot --headless --path . -s res://tests/ai_bench.gd -- 2 1 40 16`
(livello A, livello B, numero di corse, finali per carta).

## Tour a tappe (regole del Grand Tour)
Nel menu "Percorso → Tour" si sceglie il tour: Tour de France 2018 con le 21 carte tappa di
Gigamic (Fontenay-le-Comte … Champs-Élysées, con i giorni di riposo dopo la 9ª e la 15ª),
Tour de France 2018 di L'Étape du Tour (20 tappe), le classiche,
le tappe del gioco base, quelle della Companion App, oppure 3 o 6 tappe casuali. Si gioca con
le regole del regolamento di Flamme Rouge – Grand Tour.

- **Tempi di tappa**: dal turno in cui arriva il primo corridore, chi non ha ancora tagliato
  il traguardo prende un gettone da 1 minuto a ogni turno. I secondi si leggono sulla tavola
  dei tempi, nella casella del primo corridore del gruppo con cui si arriva:
  - arrivo in pianura: +0:40, +0:30, +0:20, +0:10, poi +0:00;
  - arrivo in salita: +0:30, +0:20, +0:10, poi +0:00.
- **Podio**: 3, 2 e 1 punti Tour ai primi tre di ogni tappa.
- **Fatica**: chi ha già tagliato il traguardo non la prende. Tra una tappa e l'altra ogni
  corridore smaltisce metà delle carte fatica, arrotondata per difetto (opzione nel menu).
- **Traguardi sprint e montagna**: gettoni Major (5/3/1) e Minor (2/1), piazzati con le
  regole "Designing Stages". Il Major va dopo la salita più lunga di almeno 5 caselle,
  altrimenti, come sprint, dopo l'arrivo. Il Minor va dopo l'arrivo, oppure dopo la salita
  più lunga rimasta, oppure a metà tappa. Chi raggiunge o supera un mucchietto prende un
  gettone, il più avanzato quello più alto. In pista i mucchietti stanno a bordo strada.
- **Maglie**: gialla (tempo più basso), verde (più punti sprint), a pois (più punti
  montagna). Un corridore ne porta una sola, con priorità gialla, verde, pois. A parità
  vince chi ha tagliato prima il traguardo nell'ultima tappa. In pista si vede un anello del
  colore della maglia attorno alla basetta.
- **Giorni di riposo**: obbligatori nei tour da 15 tappe o più (dopo la 9ª e la 15ª), uno a
  metà facoltativo in quelli più corti. I leader delle tre classifiche prendono 1 punto Tour
  ciascuno, gli altri corridori smaltiscono un'altra metà della fatica.
- **Schieramento**: dalla seconda tappa si schiera per prima la squadra con meno punti Tour.
- **Fine del tour**: punti bonus per classifica generale, a squadre, sprint e montagna,
  secondo la tabella del regolamento (3–7, 8–14, 15–21 tappe). Vince la squadra con più punti
  Tour (podi + bonus + giorni di riposo).

## Rilievo
Le tessere si piegano dove ci sono salite e discese: ogni casella in salita alza la
strada, ogni discesa la abbassa, e il resto del percorso resta alla quota raggiunta.
La quota più bassa della tappa coincide con il tavolo, color terra ocra. Sotto i tratti
rialzati ci sono argini con l'erba presa dalle scansioni (`assets/erba_argine.png`),
che alla base sfuma in terra, e i corridori si inclinano secondo la pendenza.
- **Rilievo** nel menu iniziale: Piatto, Leggero, Normale (dislivello del 10% per
  casella) o Marcato. È solo grafica e non cambia le regole.
- Nel pannello c'è il profilo altimetrico della tappa con la posizione dei corridori.

## Percorsi
- **Tappa dal libretto**: i 5 percorsi del regolamento base e i 56 di L'Étape du Tour,
  divisi tra versioni a 5–6 giocatori, Companion App, Tour de France 2018, classiche e
  altre tappe. Per queste non si fa il controllo delle sovrapposizioni: in alcuni
  percorsi ad anello partenza e arrivo si toccano, e lì le tessere si accavallano di
  meno di una casella.
- **Casuale**: usa ogni tessera fisica una sola volta, su un lato a caso, ed evita
  le sovrapposizioni. Lunghezze: Breve (10 tessere centrali), Media (14),
  Completa (19, tutte quelle del gioco base), Tutte (comprese quelle di Peloton se attive).
- **Sequenza di tessere**: l'anteprima si aggiorna a ogni faccia scritta, e il messaggio
  sotto dice cosa manca (partenza, arrivo) o se una faccia non esiste. Si scrivono le facce in ordine, ad esempio
  `a b c d e f g h i j k l m n o p q r s t u`. La maiuscola indica il lato scuro.
  Le tessere di Peloton si scrivono 1 … 9, lato scuro 1B … 9B. Serve per ricostruire
  i percorsi del regolamento.

## Struttura
- `data/faces.json`: le 60 facce. Per ognuna ci sono texture, punto e direzione
  d'ingresso e d'uscita (in pixel della scansione) e le caselle nel senso di marcia,
  con il terreno e la posizione di ogni corsia.
- `assets/faces/*.webp`: le scansioni ritagliate, con nomi come `g_chiaro.webp` e `g_scuro.webp`.
  I nomi non dipendono dalle maiuscole: sul Mac `g.webp` e `G.webp` sarebbero lo stesso file.
- `scripts/rules.gd`: le regole (mazzi, salita, discesa, rifornimento, pavé, scia, fatica, CPU).
- `scripts/track.gd`: il montaggio del percorso e il controllo delle sovrapposizioni.
- `scripts/generator.gd`: il generatore casuale.
- `scripts/board3d.gd`: la scena 3D. `scripts/main.gd`: l'interfaccia e i turni.
- `tests/sim.gd`: corse simulate senza grafica.
  Si lancia con `godot --headless --path . -s res://tests/sim.gd`.
- `tests/shot.gd`: fotografie della scena.

## Ipotesi da confermare
- Le caselle dopo il traguardo della faccia U sono considerate in salita.
- I riquadri gialli delle tessere 2 e 2B segnano la zona della fuga: la variante
  Breakaway non è ancora implementata.
- Terreno delle curve:
  - salita su E, G, O, K, Q, R;
  - discesa su P e H;
  - le altre sono in pianura.

## Limiti noti
- Le facce J, T e K hanno perso qualche millimetro di bordo in alto nella scansione.
- Mancano le tessere di Grand Tour.
- Le curve sono montate con la geometria ideale (90° e 45°, raggio comune), presa
  dalle scansioni solo per il punto d'aggancio: le piccole differenze tra una
  scansione e l'altra si sommavano sui percorsi lunghi.
- La CPU fa vincere più spesso i rouleur: i sprinteur vanno resi più aggressivi nel finale.
