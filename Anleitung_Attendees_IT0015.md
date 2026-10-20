# Report ZHR_ATTENDEES_IT0015

Standalone-Report ohne Includes fuer die drei Attendees-Exporte. Der bestehende
Report ZHR_STOERFALL_IT0015 bleibt unveraendert.

## Voraussetzungen und Start

- SAP HCM mit PA0105, P0015 und HR_INFOTYPE_OPERATION; ABAP-Syntax ab 7.50.
- abap2xlsx mit ZCL_EXCEL_READER_2007, ZIF_EXCEL_READER und
  ZCL_EXCEL_WORKSHEET, insbesondere dessen oeffentlicher SHEET_CONTENT-Tabelle.
- SAP GUI im Dialog, lokale XLSX-Dateien.
- Im Feld S_FILE mit F4 mehrere Dateien auswaehlen (Strg/Umschalt).
  Pflichtfeld: Mindestens ein konkreter Dateipfad muss angegeben werden.
  Jeder Pfad wird als eigener Einzelwert in der Select-Option gespeichert.
  Alle Pfade sind ueber die Mehrfachselektion einsehbar und aenderbar.
  Bei jedem Start wird die Uploadliste daraus vollstaendig neu aufgebaut;
  nach Rueckkehr aus der ALV-Liste bleiben alle ausgewaehlten Dateien erhalten.
  Die vollstaendige Dateiliste kann auch in einer Selektionsvariante gespeichert
  werden. Alte Varianten mit P_FILE bitte mit S_FILE neu speichern.
  Abbrechen im F4-Dialog erhaelt die vorherige Auswahl; bestaetigte Auswahl
  ersetzt die Liste. Nur einzelne eingeschlossene Pfade sind erlaubt,
  keine Intervalle, Ausschluesse oder Dateimuster. Maximal 255 Zeichen je Pfad;
  laengere Dialogpfade werden abgewiesen, nicht abgeschnitten.
- Die Rahmen des Selektionsbilds haben keine Titel.
- Optional S_WDID (Beschriftung: SAP-Personalnummer): Select-Option vom Typ
  PERNR_D, ausschliesslich gegen die ermittelte SAP-Personalnummer PERNR.
  Mehrfachwerte, Intervalle und Ausschluesse sind moeglich. Der technische
  Selektionsname bleibt S_WDID; Attendee ID wird damit nicht gefiltert.
  Ohne Einschraenkung werden alle Zeilen verarbeitet. Die Selektion greift
  nach Personalnummernermittlung und vor Summierung, Buchung und Ergebnisliste.
- Optional S_EXPT: Select-Option fuer Expense Type, mit Mehrfachwerten,
  Intervallen, Mustern und Ausschluessen.
- Optional S_EXPS: entsprechende Select-Option fuer Expense Sub-Type.
  Alle gesetzten Filter werden mit UND verknuepft.
- P_HIDE ist standardmaessig aktiv: Zeilen ohne ermittelte SAP-Personalnummer
  in der ALV-Anzeige ausblenden. Deaktivieren zeigt diese Fehlerzeilen wieder.
  Intern bleiben sie in GT_DATA erhalten; es ist eine reine Anzeigeoption.
- Lohnart und Stichtag vorgeben. Der Stichtag gilt fuer WDID, IT0001 und IT0015.
  Die Lohnart ist fest 5570 und wird nur angezeigt. Auch Varianten und SUBMIT
  koennen keine abweichende Lohnart fuer die Buchung setzen.
  Vorgabe ist der letzte Kalendertag des Vormonats, ausgehend vom SAP-Systemdatum.
  Beispiel: Start am 19.10.2026 -> 30.09.2026. Der Wert bleibt aenderbar.
- Die Waehrung ist fest EUR; kein Waehrungsparameter im Selektionsbild.
- **Datenbankupdate ist standardmaessig AUS.** Erst Testprotokoll pruefen.

Bei direkter Anlage in SE38 die Selektionsbeschriftungen aus der PROG.XML
uebernehmen. Bei abapGit werden sie zusammen mit dem Report eingespielt.

## Ablauf und interne Tabelle GT_DATA

1. Alle angegebenen Dateien lesen und die 19 Ueberschriften A:S exakt gegen
   Zeile 1 des ersten Tabellenblatts pruefen. Keine Buchung, wenn eine Datei
   nicht geladen werden kann oder eine andere Struktur hat.
2. Leere Zeilen ignorieren. Unerwartete Inhalte rechts von S fuehren zum
   Abbruch des Imports. Formeln werden je Datenzeile als Fehler protokolliert.
3. GT_DATA enthaelt zuerst FILENAME (Basisname), danach die 19 Quellfelder in
   Originalreihenfolge, dann PERNR als zweites neu hinzugefuegtes Feld.
   Es folgen SAP_NAME (IT0001-ENAME), EXCEL_ROW, SAP_AMOUNT, STATUS_ICON,
   STATUS und zuletzt REMARK. Es gibt kein Satznummernfeld.
4. Die beiden Betragsspalten N/O und das Buchungsfeld SAP_AMOUNT werden als
   MAXBT konvertiert. TRANSACTION_DT (Spalte M) ist ein echtes SAP-Datum
   (TYPE D): Excel-Seriennummern im 1900-Datumssystem werden ueber
   ZCL_EXCEL_COMMON=>EXCEL_STRING_TO_DATE umgerechnet. Ein Zeitanteil wird
   ohne Aufrunden abgeschnitten. Ungueltige Werte werden als Zeilenfehler
   protokolliert; leere Datumszellen bleiben leer. Die ALV verwendet das
   Datumsformat des Benutzers. PAYMENT_DATE und die anderen Quellfelder
   bleiben Strings. Fuer die Buchung gilt weiterhin allein der vorgegebene Stichtag.
   Vor Filterung und Personalnummernermittlung werden Zeilen mit leerer oder
   nicht rein numerischer Attendee ID entfernt (auch Leerzeichen, Vorzeichen,
   Dezimalpunkt und Exponentialnotation gelten als nichtnumerisch).
   Bei den verbleibenden IDs werden fuehrende Nullen entfernt; eine ID nur aus
   Nullen bleibt als '0' erhalten. Diese Bereinigung betrifft nur die
   WDID-Zuordnung. S_WDID filtert anschliessend die ermittelte SAP-Personalnummer.
   Die Anzahl entfernter Zeilen erscheint im ALV-Titel.
5. ATTENDEE_ID wird exakt mit USRID oder USRID_LONG in PA0105, Subtyp WDID,
   verglichen. Nur am Stichtag gueltige, nicht gesperrte Saetze zaehlen.
   Fehlende und mehreren Personalnummern zugeordnete IDs sind Fehler.
   Eine berechtigte HR_READ_INFOTYPE-Lesepruefung bestaetigt jeden Treffer.
   Das Ergebnis wird pro ID zwischengespeichert.
   SAP_NAME stammt aus dem am Stichtag gueltigen, nicht gesperrten IT0001-Satz,
   gelesen mit HR_READ_INFOTYPE. Fehlende, mehrdeutige oder nicht berechtigt
   lesbare IT0001-Daten werden als Fehler protokolliert.
6. AMOUNT_TRANS ist ausschliesslich Approved Amount (Transaction Currency),
   Excel-Spalte N. Spalte O wird nicht gebucht. Dezimalpunkt, kein
   Tausendertrennzeichen. Excel-Gleitkommaartefakte wie 16.899999999999999
   werden auf 16.90 normalisiert (maximale Abweichung 0.00000001).
   Echte Bruchteile eines Cents werden abgelehnt; keine fachliche Rundung.
   Nullbetraege werden mit Status HINWEIS und dem Text 'Nullbetrag wird nicht
   gebucht.' uebersprungen. Sie sind kein Fehler und loesen allein keine rote
   Ampel aus. Negative Betraege werden zugelassen und bei
   Echtbuchung gegen das SAP-Customizing geprueft.
7. Ergebnis als SALV anzeigen. Standardmaessig sind FILENAME, COMPANY_CODE,
   COMPANY_NAME, GROUP_ID, PAYMENT_DATE sowie REPORT_KEY, REPORT_ID,
   EXPENSE_SUBTYPE, ENTRY_KEY, TRANSACTION_DT, TRIP_PURPOSE,
   VENDOR, ATTENDEE_COUNT sowie EXCEL_ROW und SAP_AMOUNT ausgeblendet.
   Sie bleiben intern vorhanden und koennen ueber die Spaltenauswahl wieder
   eingeblendet werden.
   COMMENTS hat eine feste Anzeigebreite von 40 Zeichen; der vollstaendige
   Inhalt bleibt erhalten. Die ersten drei ALV-Spalten sind Ampel,
   SAP-Personalnummer und SAP_NAME aus IT0001-ENAME. Die Ampel zeigt:
   Rot, sobald die Personalnummer mindestens eine Fehlerzeile hat. Ohne Fehler
   Gruen bei einer Summe von AMOUNT_TRANS je Personalnummer ueber 50 EUR,
   ansonsten Gelb (einschliesslich genau 50 EUR). Zeilen ohne Personalnummer
   und mit Fehlerstatus bleiben Rot.
   Nach Personalnummer wird aufsteigend sortiert. Beide Betragsspalten N/O
   erhalten Zwischensummen pro Personalnummer und eine Gesamtsumme. Summen und
   Ampel beziehen sich auf die nach Bereinigung und Selektion verbliebenen Zeilen.
   Expense Type ist wieder sichtbar. Mehrere Importzeilen derselben Person
   sind erlaubt und werden fuer die Anzeige summiert.
   Der technische Statustext bleibt intern und ist standardmaessig ausgeblendet.
   Die ersten drei Spalten (Ampel, SAP-Personalnummer und Name aus IT0001) sind als
   Schluesselspalten fixiert und bleiben beim horizontalen Scrollen sichtbar.

## Test und Buchung

**Ohne Datenbankupdate**: Dateiformat, WDID, IT0001-Name, Betragskonvertierung,
Gesamtsumme je Personalnummer und vorhandene IT0015-Saetze pruefen.
Mehrere Importzeilen derselben Personalnummer sind erlaubt.
Kein Sperren, kein HR_INFOTYPE_OPERATION, kein COMMIT.
STATUS TEST bedeutet Vorpruefung erfolgreich; es ist keine Simulation der
SAP-Schreibberechtigung, Lohnartenzulaessigkeit oder dynamischer Massnahmen.
Der angezeigte Erfolgstext lautet 'Prüfung OK'. Der Umlaut wird im Programm
als Unicode-Zeichen U+00FC erzeugt. Der ABAP-Quelltext selbst ist ASCII,
damit auch beim Kopieren oder Importieren als ANSI keine Umlaute zerstoert werden.

**Mit Datenbankupdate** wird pro Personalnummer genau eine Gesamtbuchung
vorbereitet. Alle nach Bereinigung und Selektion verbliebenen Transaktionsbetraege
(Spalte N) dieser Person aus allen ausgewaehlten Dateien werden addiert.
Die Summe wird auf verlustfreie Darstellbarkeit als MAXBT geprueft.
Hat eine dieser Zeilen einen Fehler, wird die gesamte Personalnummer nicht
gebucht. Ein Gesamtbetrag von null ist ein Hinweis ohne Buchung.

- Mitarbeiter mit BAPI_EMPLOYEE_ENQUEUE sperren.
- Alle unterschiedlichen WDID-Zuordnungen der zugehoerigen Quellzeilen unter
  der Sperre erneut pruefen.
- Vorhandene IT0015-Saetze erneut lesen. Ist die Lohnart am Stichtag bereits
  vorhanden (BEGDA <= Stichtag <= ENDDA), Fehler statt Buchung. Auch gesperrte
  Saetze blockieren. Diese Pruefung erfolgt innerhalb der Mitarbeitersperre.
  HR_READ_INFOTYPE-SUBRC 0 und 8 sind regulaere Ergebnisse (vollstaendige
  Rueckgabe bzw. keine Saetze im Zeitraum). SUBRC 4/12 zeigen eingeschraenkten
  Zugriff an und blockieren die Buchung. Technische Ausnahmen werden separat
  mit CALL-SUBRC protokolliert; unbekannte Rueckgabewerte mit SUBRC.
- P0015 mit BEGDA = ENDDA = Stichtag, LGART = SUBTY = Parameter-Lohnart,
  BETRG = Personengesamtsumme (SAP_AMOUNT im Buchungssatz) und WAERS = EUR
  fuellen; keine Satznummernvergabe.
- HR_INFOTYPE_OPERATION genau einmal je fehlerfreier Personalnummer mit
  INS, TCLAS A, DIALOG_MODE 0, NOCOMMIT X aufrufen.
  Die interne Schreibberechtigungspruefung dieses Standardbausteins bleibt
  aktiv. Seine Schnittstelle bietet keinen NO_AUTH_CHECK-Parameter. Ein
  Abschalten erfordert einen anderen Schreibweg; es wird kein wirkungsloser
  Schalter und keine direkte Datenbankbuchung als Ersatz eingebaut.
- Bei Erfolg COMMIT WORK AND WAIT, bei Fehler ROLLBACK WORK.
- Mitarbeitersperre loesen und HR-Puffer zuruecksetzen.

Alle Importzeilen bleiben fuer die Detailanzeige erhalten. N/O und die interne
SAP_AMOUNT-Spalte der Detailzeilen enthalten weiterhin die jeweiligen
Einzelbetraege; nur der separate Buchungssatz traegt die Personengesamtsumme.
Das Ergebnis der einen Gesamtbuchung wird auf alle Zeilen der Personalnummer
uebertragen. Null-Einzelzeilen behalten einen Hinweis, sofern die Gruppe
keinen Fehler hat. Im Test entstehen keine neuen IT0015-Saetze.
Bestehende Saetze werden weder geaendert noch geloescht. Ein Fehler blockiert
die Gesamtbuchung der betroffenen Person, nicht die anderen Personalnummern.
Bereits erfolgreich gebuchte Personalnummern bleiben bei einem spaeteren
Fehler einer anderen Person bestehen.

Ein erneuter Echtlauf fuer dieselbe Personalnummer/Lohnart/Stichtag wird durch
die IT0015-Bestandspruefung mit Fehler abgewiesen. Es wird kein persistentes
Importjournal gefuehrt. Eine Aenderung des Stichtags oder der Lohnart erzeugt
einen anderen Zielschluessel und wird durch diese Pruefung nicht blockiert.

## Pruefung mit den bereitgestellten Dateien

Lokal wurden die Kopfzeilen A1:S1 aller drei Dateien identisch bestaetigt:

| Datei | Befuellte Datenzeilen |
| --- | ---: |
| 8011 Attendees September 2026.xlsx (gekuerzte Fassung) | 11 |
| 8800 Attendees September 2026.xlsx | 890 |
| PCARD attendees September 2026.xlsx | 750 |

Die PCARD-Datei enthaelt ausserdem ueber eine Million leere XML-Zeilen.
Der Report iteriert nur ueber in SHEET_CONTENT vorhandene Zellen mit Werten
oder Formeln und die daraus ermittelten Datenzeilen. Das Laden und Parsen des
gesamten XLSX durch abap2xlsx selbst kann dennoch viel Zeit und Speicher kosten.

Kein SAP-System ist angebunden. Syntaxpruefung, Aktivierung und fachliche
Laufzeitpruefung im Zielsystem stehen aus. Dort zunaechst den Testlauf ausfuehren;
anschliessend in einem Testmandanten einzelne Echtbuchungen pruefen, insbesondere
mehrere Zeilen derselben Person, bestehende IT0015-Saetze, negative Betraege,
fehlende/mehrdeutige WDID, Berechtigungen und Mitarbeitersperren.
