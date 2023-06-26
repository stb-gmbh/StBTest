*&---------------------------------------------------------------------*
*& Report ZMBR_TEST_GIT_FIRST
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zmbr_test_peci.

PARAMETERS: p_fname TYPE file_table-filename OBLIGATORY DEFAULT 'C:\Users\Michael\Documents\ISC\PECI\MessageLog.txt'.

DATA lt_strings  TYPE TABLE OF char2048.
DATA lv_filename TYPE string.
DATA: ls_peci    TYPE zpeci_workers_effective_stack.
DATA: lt_peci    TYPE TABLE OF zpeci_workers_effective_stack.
DATA: lx_excep   TYPE REF TO cx_st_match_element .
DATA: lx_excep2  TYPE REF TO cx_st_ref_access.
DATA: lx_excep3  TYPE REF TO cx_st_match_attribute.
DATA: lv_msg     TYPE string.
DATA: lt_arbeiter TYPE zpeci_arbeiter_t.


DATA: ls_worker TYPE zpeci_worker_s.
DATA: ls_effective_change TYPE zpeci_effective_change_s.
DATA: ls_compensation_plans TYPE zpeci_compensation_plans_s.
DATA: ls_transaction_log TYPE zpeci_transaction_log_s.



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


  cl_gui_frontend_services=>gui_upload( EXPORTING
                                          filename = lv_filename
                                          filetype = 'ASC'
                                        CHANGING
                                          data_tab = lt_strings ).

  TRY.
      CALL TRANSFORMATION zpeci_test1
      SOURCE XML lt_strings
      RESULT workers_effective_stack = ls_peci.
      APPEND ls_peci TO lt_peci.
      CLEAR ls_peci.
    CATCH cx_st_match_element INTO lx_excep.
      lv_msg = lx_excep->get_text( ).
      WRITE lv_msg.
    CATCH cx_st_ref_access INTO lx_excep2.
      lv_msg = lx_excep2->get_text( ).
      WRITE lv_msg.
    CATCH cx_st_match_attribute INTO lx_excep3.
      lv_msg = lx_excep3->get_text( ).
      WRITE lv_msg.
  ENDTRY.


  BREAK-POINT.

  LOOP AT lt_peci INTO ls_peci.
    LOOP AT ls_peci-worker INTO ls_worker.
      LOOP AT ls_worker-effective_change INTO ls_effective_change.
        LOOP AT ls_effective_change-compensation_plans INTO ls_compensation_plans.
        ENDLOOP.
        LOOP AT ls_effective_change-transaction_log INTO ls_transaction_log.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDLOOP.
