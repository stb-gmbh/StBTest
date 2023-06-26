*&---------------------------------------------------------------------*
*& Report ZMBR_TEST_GIT_FIRST
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zmbr_test_git_first.

PARAMETERS: p_fname TYPE file_table-filename OBLIGATORY DEFAULT 'C:\Users\Michael\Documents\ISC\PECI\MeinPECI.txt'.

DATA lt_strings  TYPE TABLE OF char2048.
DATA lv_filename TYPE string.
DATA: ls_peci    TYPE zpeci_mitarbeiter.
DATA: lt_peci    TYPE TABLE OF zpeci_mitarbeiter.
DATA: lx_excep   TYPE REF TO cx_st_match_element .
DATA: lv_msg     TYPE string.
data: lt_arbeiter type ZPECI_ARBEITER_T.


* wenn die F4-Hilfe für den Dateinamen aufgerufen wird
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_fname.

  DATA: lv_rc TYPE i.
  DATA: it_files TYPE filetable.
  DATA: lv_action TYPE i.

* File-Tabelle leeren, da hier noch alte Einträge von vorherigen Aufrufen drin stehen können
  CLEAR it_files.

* FileOpen-Dialog aufrufen
  TRY.
      cl_gui_frontend_services=>file_open_dialog( EXPORTING
                                                    file_filter    = |txt (*.txt)\|*.txt\|{ cl_gui_frontend_services=>filetype_all }|
                                                    multiselection = abap_false
                                                  CHANGING
                                                    file_table  = it_files
                                                    rc          = lv_rc
                                                    user_action = lv_action ).

      IF lv_action = cl_gui_frontend_services=>action_ok.
* wenn Datei ausgewählt wurde
        IF lines( it_files ) > 0.
* ersten Tabelleneintrag lesen
          p_fname = it_files[ 1 ]-filename.

* tabelle für einlesedaten
        ENDIF.
      ENDIF.

    CATCH cx_root INTO DATA(e_text).
      MESSAGE e_text->get_text( ) TYPE 'I'.
  ENDTRY.


START-OF-SELECTION.
  lv_filename = CONV #( p_fname ).

* eingelesene Datei zeilenweise als Stringdaten einlesen
  cl_gui_frontend_services=>gui_upload( EXPORTING
                                          filename = lv_filename
                                          filetype = 'ASC'             " Dateityp BIN, ASC, DAT
                                        CHANGING
                                          data_tab = lt_strings ).           " Übergabetabelle für Datei-Inhalt

  TRY.
*— Data in the excel will be collected in gs_create_main.
      CALL TRANSFORMATION zpeci_test3
      SOURCE XML lt_strings
      RESULT mitarbeiter = ls_peci.
      APPEND ls_peci TO lt_peci.
      CLEAR ls_peci.
    CATCH cx_st_match_element INTO lx_excep.
      lv_msg = lx_excep->get_text( ).
      WRITE lv_msg.
  ENDTRY.


lt_arbeiter = lt_peci[ 1 ]-arbeiter.

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = DATA(lr_alv)
          CHANGING t_table = lt_arbeiter ).

      DATA(lr_functions) = lr_alv->get_functions( ).
      lr_functions->set_all( ).
      lr_alv->display( ).
    CATCH cx_salv_msg.
      MESSAGE 'ALV display not possible' TYPE 'I' DISPLAY LIKE 'E'.
  ENDTRY.
