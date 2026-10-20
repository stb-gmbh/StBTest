REPORT zhr_attendees_it0015.

* Standalone report, SAP_BASIS 750+, abap2xlsx required.
* One IT0015 record per personnel number, containing its transaction total.
* Existing IT0015 wage type on the posting date blocks a new record.
* Update OFF: read-only precheck, no HR_INFOTYPE_OPERATION call.
* Amounts: Excel decimal point. Binary noise <= 0.00000001 is normalized.
* Actual fractional cents are rejected; Transaction Date is converted to D.

TYPES: BEGIN OF ty_data,
         filename        TYPE string,
* Excel columns A:S. Amount columns N/O are converted to MAXBT.
         company_code    TYPE string,
         company_name    TYPE string,
         group_id        TYPE string,
         payment_date    TYPE string,
         attendee_id     TYPE string,
         attendee_name   TYPE string,
         employee_name   TYPE string,
         report_key      TYPE string,
         report_id       TYPE string,
         expense_type    TYPE string,
         expense_subtype TYPE string,
         entry_key       TYPE string,
         transaction_dt  TYPE sy-datum,
         amount_trans    TYPE maxbt,
         amount_reimb    TYPE maxbt,
         trip_purpose    TYPE string,
         vendor          TYPE string,
         attendee_count  TYPE string,
         comments        TYPE string,
* Second added field: SAP personnel number, after the source columns.
         pernr           TYPE pernr_d,
         sap_name        TYPE p0001-ename,
         excel_row       TYPE i,
         sap_amount      TYPE maxbt,
         status_icon     TYPE icon_d,
         status          TYPE c LENGTH 10,
         remark          TYPE string,
       END OF ty_data.
TYPES ty_t_data TYPE STANDARD TABLE OF ty_data WITH DEFAULT KEY.
TYPES ty_t_headers TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
TYPES: BEGIN OF ty_cache,
         attendee_id TYPE string,
         pernr       TYPE pernr_d,
         sap_name    TYPE p0001-ename,
         error       TYPE string,
       END OF ty_cache.
TYPES ty_t_cache TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY attendee_id.

DATA gt_data TYPE ty_t_data.
DATA gt_headers TYPE ty_t_headers.
DATA gt_cache TYPE ty_t_cache.
DATA gt_files TYPE filetable.
DATA gv_file TYPE c LENGTH 255.
DATA gv_error TYPE string.
DATA gv_pernr TYPE pernr_d.
DATA gv_expense TYPE c LENGTH 255.
DATA gv_removed TYPE i.
CONSTANTS gc_waers TYPE p0015-waers VALUE 'EUR'.
CONSTANTS gc_lgart TYPE p0015-lgart VALUE '5570'.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
SELECT-OPTIONS s_file FOR gv_file LOWER CASE OBLIGATORY NO INTERVALS.
SELECTION-SCREEN END OF BLOCK b1.
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME.
SELECT-OPTIONS s_wdid FOR gv_pernr.
SELECT-OPTIONS s_expt FOR gv_expense LOWER CASE.
SELECT-OPTIONS s_exps FOR gv_expense LOWER CASE.
PARAMETERS p_hide AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_lgart TYPE p0015-lgart DEFAULT '5570' OBLIGATORY MODIF ID lga.
PARAMETERS p_date TYPE sy-datum OBLIGATORY.
PARAMETERS p_update AS CHECKBOX DEFAULT space.
PARAMETERS p_layout TYPE disvariant-variant.
SELECTION-SCREEN END OF BLOCK b2.

INITIALIZATION.
* First day of this month minus one day, including year/leap-year boundaries.
  p_date = sy-datum.
  p_date+6(2) = '01'.
  p_date = p_date - 1.

AT SELECTION-SCREEN OUTPUT.
* Display the fixed wage type; selection variants cannot replace it.
  p_lgart = gc_lgart.
  LOOP AT SCREEN.
    IF screen-group1 = 'LGA'.
      screen-input = 0.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_file-low.
  PERFORM choose_files.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_layout.
  PERFORM choose_layout.

AT SELECTION-SCREEN.
  IF sy-batch = abap_true.
    MESSAGE 'Lokaler XLSX-Upload erfordert SAP GUI im Dialog.' TYPE 'E'.
  ENDIF.
  IF s_file[] IS INITIAL.
    MESSAGE 'Bitte mindestens eine Excel-Datei auswaehlen.' TYPE 'E'.
  ENDIF.
  LOOP AT s_file INTO DATA(ls_file_option).
    IF ls_file_option-sign <> 'I' OR ls_file_option-option <> 'EQ' OR
       ls_file_option-low IS INITIAL.
      MESSAGE 'Dateien: nur einzelne eingeschlossene Dateipfade erlaubt.'
        TYPE 'E'.
    ENDIF.
  ENDLOOP.
  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING date = p_date
    EXCEPTIONS plausibility_check_failed = 1 OTHERS = 2.
  IF sy-subrc <> 0.
    MESSAGE 'Ungueltiger Stichtag.' TYPE 'E'.
  ENDIF.
  PERFORM check_currency CHANGING gv_error.
  IF gv_error IS NOT INITIAL.
    MESSAGE gv_error TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
* Enforce the same value for SUBMIT/variants as for interactive execution.
  p_lgart = gc_lgart.
  CLEAR: gt_data, gt_cache, gv_error, gv_removed.
  PERFORM prepare_files.
  PERFORM headers_init.
* All selected files must load successfully before any posting starts.
  TRY.
      LOOP AT gt_files INTO DATA(ls_selected).
        DATA(lv_path) = CONV string( ls_selected-filename ).
        PERFORM read_file USING lv_path CHANGING gv_error.
        IF gv_error IS NOT INITIAL.
          EXIT.
        ENDIF.
      ENDLOOP.
    CATCH cx_root INTO DATA(lx_import).
      gv_error = lx_import->get_text( ).
  ENDTRY.
  IF gv_error IS NOT INITIAL.
    MESSAGE gv_error TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  IF gt_data IS INITIAL.
    MESSAGE 'Keine Datenzeilen gefunden.' TYPE 'S'.
    RETURN.
  ENDIF.
  PERFORM clean_attendee_ids.
  PERFORM filter_expenses.
  IF gt_data IS INITIAL.
    MESSAGE 'Keine Daten nach ID-Bereinigung und Selektionsfiltern vorhanden.'
      TYPE 'S'.
    RETURN.
  ENDIF.
  PERFORM determine_personnel_numbers.
  PERFORM filter_personnel_numbers.
  IF gt_data IS INITIAL.
    MESSAGE 'Keine Daten fuer die selektierten SAP-Personalnummern gefunden.'
      TYPE 'S'.
    RETURN.
  ENDIF.
  PERFORM process_data.
  PERFORM display_result.

FORM choose_layout.
  DATA ls_key TYPE salv_s_layout_key.
  DATA ls_layout TYPE salv_s_layout_info.
* Use the same report key and save restriction as the displayed ALV.
  ls_key-report = sy-repid.
  TRY.
      ls_layout = cl_salv_layout_service=>f4_layouts(
        s_key = ls_key restrict = if_salv_c_layout=>restrict_none ).
* Cancel preserves a layout already entered on the selection screen.
      IF ls_layout-layout IS NOT INITIAL.
        p_layout = ls_layout-layout.
      ENDIF.
    CATCH cx_root INTO DATA(lx_layout).
      DATA(lv_error) = lx_layout->get_text( ).
      MESSAGE lv_error TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

FORM choose_files.
  DATA lt_files TYPE filetable.
  DATA lt_selection LIKE s_file[].
  DATA ls_selection LIKE LINE OF lt_selection.
  DATA lv_filename TYPE string.
  DATA lv_rc TYPE i.
  DATA lv_action TYPE i.
  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING file_filter = 'Excel (*.xlsx)|*.xlsx|'
      multiselection = abap_true
    CHANGING file_table = lt_files rc = lv_rc user_action = lv_action
    EXCEPTIONS OTHERS = 1 ).
  IF sy-subrc = 0 AND lv_rc > 0 AND
     lv_action = cl_gui_frontend_services=>action_ok.
* Build the complete selection before replacing it; cancel/error preserves it.
    LOOP AT lt_files INTO DATA(ls_file).
      lv_filename = ls_file-filename.
      IF strlen( lv_filename ) > 255.
        MESSAGE 'Dateipfad laenger als 255 Zeichen; Auswahl nicht uebernommen.'
          TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
      CLEAR ls_selection.
      ls_selection-sign = 'I'.
      ls_selection-option = 'EQ'.
      ls_selection-low = ls_file-filename.
      IF NOT line_exists( lt_selection[ low = ls_selection-low ] ).
        APPEND ls_selection TO lt_selection.
      ENDIF.
    ENDLOOP.
    s_file[] = lt_selection.
    READ TABLE s_file INDEX 1.
  ENDIF.
ENDFORM.

FORM prepare_files.
* Rebuild working list on EVERY execution from the actual selection screen.
* S_FILE survives list return/re-execution and can be saved in variants.
  CLEAR gt_files.
  LOOP AT s_file INTO DATA(ls_file_selection).
    IF NOT line_exists( gt_files[ filename = ls_file_selection-low ] ).
      APPEND VALUE #( filename = ls_file_selection-low ) TO gt_files.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM clean_attendee_ids.
  DATA lv_index TYPE sy-tabix.
  LOOP AT gt_data ASSIGNING FIELD-SYMBOL(<data>).
    lv_index = sy-tabix.
* Reject whitespace, signs, decimal points, exponent notation and empty IDs.
    FIND REGEX '^[0-9]+$' IN <data>-attendee_id.
    IF sy-subrc <> 0.
      DELETE gt_data INDEX lv_index.
      gv_removed = gv_removed + 1.
      CONTINUE.
    ENDIF.
    SHIFT <data>-attendee_id LEFT DELETING LEADING '0'.
    IF <data>-attendee_id IS INITIAL.
      <data>-attendee_id = '0'.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM filter_expenses.
* Source expense selection can run before personnel-number lookup.
  IF s_expt[] IS NOT INITIAL.
    DELETE gt_data WHERE expense_type NOT IN s_expt.
  ENDIF.
  IF s_exps[] IS NOT INITIAL.
    DELETE gt_data WHERE expense_subtype NOT IN s_exps.
  ENDIF.
ENDFORM.

FORM filter_personnel_numbers.
* S_WDID keeps its technical name but selects the resolved SAP PERNR only.
* Apply before aggregation so all retained rows of a person form its total.
  IF s_wdid[] IS NOT INITIAL.
    DELETE gt_data WHERE pernr NOT IN s_wdid.
  ENDIF.
ENDFORM.

FORM check_currency CHANGING cv_error TYPE string.
  DATA lv_currency TYPE tcurc-waers.
  DATA lv_decimals TYPE tcurx-currdec.
  CLEAR cv_error.
  SELECT SINGLE waers FROM tcurc INTO lv_currency WHERE waers = gc_waers.
  IF sy-subrc <> 0.
    cv_error = 'Waehrung existiert nicht in TCURC.'.
    RETURN.
  ENDIF.
  SELECT SINGLE currdec FROM tcurx INTO lv_decimals
    WHERE currkey = gc_waers.
  IF sy-subrc = 0 AND lv_decimals <> 2.
    cv_error = 'Dieser Report unterstuetzt Waehrungen mit 2 Dezimalstellen.'.
  ENDIF.
ENDFORM.

FORM headers_init.
  gt_headers = VALUE #(
    ( `Company Code` )
    ( `Company Code Name` )
    ( `Group ID` )
    ( `Sent for Payment Date` )
    ( `Attendee ID` )
    ( `Attendee Name` )
    ( `Employee Name` )
    ( `Report Legacy Key` )
    ( `Report ID` )
    ( `Expense Type` )
    ( `Expense Sub-Type` )
    ( `Entry Key` )
    ( `Transaction Date` )
    ( `Approved Amount (Transaction Currency)` )
    ( `Approved Amount (Reimbursement Currency)` )
    ( `Trip Purpose` )
    ( `Vendor` )
    ( `Number of Attendees` )
    ( `Comments` ) ).
ENDFORM.

FORM read_file USING iv_file TYPE string CHANGING cv_error TYPE string
  RAISING zcx_excel.
  DATA lo_reader TYPE REF TO zif_excel_reader.
  DATA lo_excel TYPE REF TO zcl_excel.
  DATA lo_sheet TYPE REF TO zcl_excel_worksheet.
  DATA lt_rows TYPE SORTED TABLE OF zexcel_cell_row
               WITH UNIQUE KEY table_line.
  DATA ls_data TYPE ty_data.
  DATA lv_value TYPE zexcel_cell_value.
  DATA lv_formula TYPE zexcel_cell_formula.
  DATA lv_file TYPE string.
  DATA lv_component TYPE i.
  DATA lv_raw_amount TYPE string.
  DATA lv_amount TYPE maxbt.
  DATA lv_amount_error TYPE string.
  DATA lv_amount_message TYPE string.
  DATA lv_date_error TYPE string.
  FIELD-SYMBOLS <cell> TYPE zexcel_s_cell_data.
  FIELD-SYMBOLS <value> TYPE any.

  CLEAR cv_error.
  lv_file = iv_file.
  REPLACE ALL OCCURRENCES OF '\' IN lv_file WITH '/'.
  FIND REGEX '[^/]+$' IN lv_file MATCH OFFSET DATA(lv_offset).
  IF sy-subrc = 0.
    lv_file = lv_file+lv_offset.
  ENDIF.
  CREATE OBJECT lo_reader TYPE zcl_excel_reader_2007.
  lo_excel = lo_reader->load_file(
    i_filename = iv_file i_from_applserver = abap_false ).
  lo_sheet = lo_excel->get_worksheet_by_index( iv_index = 1 ).
  IF lo_sheet IS NOT BOUND.
    cv_error = |{ lv_file }: Erstes Tabellenblatt fehlt.|.
    RETURN.
  ENDIF.
  LOOP AT gt_headers INTO DATA(lv_header).
    DATA(lv_col) = sy-tabix.
    CLEAR: lv_value, lv_formula.
    lo_sheet->get_cell( EXPORTING ip_column = lv_col ip_row = 1
      IMPORTING ep_value = lv_value ep_formula = lv_formula ).
    IF lv_value <> lv_header OR lv_formula IS NOT INITIAL.
      cv_error = |{ lv_file }: Spalte { lv_col }, erwartet: { lv_header }|.
      RETURN.
    ENDIF.
  ENDLOOP.
* Sparse iteration: no DO get_highest_row() over a million empty rows.
* abap2xlsx still parses the source XML; huge formatted exports cost memory.
  LOOP AT lo_sheet->sheet_content ASSIGNING <cell>.
    IF <cell>-cell_value IS INITIAL AND <cell>-cell_formula IS INITIAL.
      CONTINUE.
    ENDIF.
    IF <cell>-cell_column > 19.
      cv_error = |{ lv_file }: Unerwarteter Inhalt rechts von Spalte S.|.
      RETURN.
    ENDIF.
    IF <cell>-cell_row > 1.
      INSERT <cell>-cell_row INTO TABLE lt_rows.
    ENDIF.
  ENDLOOP.
  IF lt_rows IS INITIAL.
    cv_error = |{ lv_file }: Keine Datenzeilen vorhanden.|.
    RETURN.
  ENDIF.
  LOOP AT lt_rows INTO DATA(lv_row).
    CLEAR ls_data.
    ls_data-filename = lv_file.
    ls_data-excel_row = lv_row.
    DO 19 TIMES.
      lv_col = sy-index.
      lv_component = lv_col + 1.
      ASSIGN COMPONENT lv_component OF STRUCTURE ls_data TO <value>.
      CLEAR: lv_value, lv_formula.
      lo_sheet->get_cell( EXPORTING ip_column = lv_col ip_row = lv_row
        IMPORTING ep_value = lv_value ep_formula = lv_formula ).
      IF lv_col = 14 OR lv_col = 15.
        lv_raw_amount = lv_value.
        PERFORM convert_amount USING lv_raw_amount
          CHANGING lv_amount lv_amount_error.
        <value> = lv_amount.
        IF lv_amount_error IS NOT INITIAL.
          ls_data-status = 'FEHLER'.
          lv_amount_message = |Spalte { lv_col }: { lv_amount_error }|.
          PERFORM add_remark USING lv_amount_message
            CHANGING ls_data-remark.
        ENDIF.
      ELSEIF lv_col = 13.
        PERFORM convert_transaction_date USING lv_value
          CHANGING ls_data-transaction_dt lv_date_error.
        IF lv_date_error IS NOT INITIAL.
          ls_data-status = 'FEHLER'.
          PERFORM add_remark USING lv_date_error CHANGING ls_data-remark.
        ENDIF.
      ELSE.
        <value> = lv_value.
      ENDIF.
      IF lv_formula IS NOT INITIAL.
        ls_data-status = 'FEHLER'.
        ls_data-remark = |Formel in Spalte { lv_col }; Werte exportieren.|.
      ENDIF.
    ENDDO.
    APPEND ls_data TO gt_data.
  ENDLOOP.
ENDFORM.

FORM convert_transaction_date USING iv_value TYPE zexcel_cell_value
                              CHANGING cv_date TYPE sy-datum
                                       cv_error TYPE string.
  DATA lv_serial TYPE decfloat34.
  DATA lv_day TYPE i.
  DATA lv_excel_day TYPE zexcel_cell_value.
  CLEAR: cv_date, cv_error.
  IF iv_value IS INITIAL.
    RETURN.
  ENDIF.
  TRY.
      lv_serial = iv_value.
      IF lv_serial < 1 OR lv_serial >= 2958466.
        cv_error = |Transaction Date: ungueltige Excel-Seriennummer '{ iv_value }'.|.
        RETURN.
      ENDIF.
* Ignore the optional time fraction without rounding to the next date.
      lv_day = trunc( lv_serial ).
      IF lv_day = 60.
        cv_error = 'Transaction Date: Excel-Datum 29.02.1900 existiert nicht.'.
        RETURN.
      ENDIF.
      lv_excel_day = |{ lv_day NUMBER = RAW }|.
      cv_date = zcl_excel_common=>excel_string_to_date(
        ip_value = lv_excel_day ).
    CATCH cx_root INTO DATA(lx_date).
      cv_error = |Transaction Date '{ iv_value }': { lx_date->get_text( ) }|.
  ENDTRY.
ENDFORM.

* Exact WDID match, valid and unlocked at the chosen posting date.
* SQL finds candidates only. HR_READ_INFOTYPE checks HR read authorization.
FORM find_pernr USING iv_attendee TYPE string
                CHANGING cv_pernr TYPE pernr_d cv_error TYPE string.
  DATA lt_pernr TYPE SORTED TABLE OF pernr_d WITH UNIQUE KEY table_line.
  DATA lt_0105 TYPE STANDARD TABLE OF p0105.
  DATA lv_usrid TYPE pa0105-usrid.
  DATA lv_long TYPE pa0105-usrid_long.
  DATA lv_rc TYPE sy-subrc.
  CLEAR: cv_pernr, cv_error.
  IF iv_attendee IS INITIAL.
    cv_error = 'Attendee ID fehlt; Personalnummer nicht ermittelbar.'.
    RETURN.
  ENDIF.
  IF strlen( iv_attendee ) > 30.
    cv_error = 'Attendee ID laenger als 30 Zeichen; WDID nicht zuordenbar.'.
    RETURN.
  ENDIF.
  lv_usrid = iv_attendee.
  lv_long = iv_attendee.
  SELECT DISTINCT pernr FROM pa0105 INTO TABLE lt_pernr
    WHERE subty = 'WDID' AND sprps = space
      AND begda <= p_date AND endda >= p_date
      AND ( usrid = lv_usrid OR usrid_long = lv_long ).
  IF lt_pernr IS INITIAL.
    cv_error = 'Personalnummer nicht ermittelbar: kein gueltiger WDID-Satz.'.
    RETURN.
  ELSEIF lines( lt_pernr ) > 1.
    cv_error = 'WDID mehreren Personalnummern zugeordnet; keine Buchung.'.
    RETURN.
  ENDIF.
  READ TABLE lt_pernr INDEX 1 INTO DATA(lv_pernr).
  CALL FUNCTION 'HR_READ_INFOTYPE'
    EXPORTING pernr = lv_pernr infty = '0105'
      begda = p_date endda = p_date bypass_buffer = 'X'
    IMPORTING subrc = lv_rc
    TABLES infty_tab = lt_0105
    EXCEPTIONS infty_not_found = 1 OTHERS = 2.
  IF sy-subrc <> 0 OR lv_rc <> 0.
    cv_error = 'IT0105 nicht vollstaendig berechtigt lesbar.'.
    RETURN.
  ENDIF.
  LOOP AT lt_0105 TRANSPORTING NO FIELDS
    WHERE subty = 'WDID' AND sprps = space
      AND begda <= p_date AND endda >= p_date
      AND ( usrid = lv_usrid OR usrid_long = lv_long ).
    cv_pernr = lv_pernr.
    EXIT.
  ENDLOOP.
  IF cv_pernr IS INITIAL.
    cv_error = 'Kein berechtigt lesbarer, gueltiger WDID-Satz.'.
  ENDIF.
ENDFORM.

FORM determine_personnel_numbers.
  DATA ls_cache TYPE ty_cache.
  LOOP AT gt_data ASSIGNING FIELD-SYMBOL(<data>).
    READ TABLE gt_cache INTO ls_cache
      WITH TABLE KEY attendee_id = <data>-attendee_id.
    IF sy-subrc <> 0.
      CLEAR ls_cache.
      ls_cache-attendee_id = <data>-attendee_id.
      PERFORM find_pernr USING ls_cache-attendee_id
        CHANGING ls_cache-pernr ls_cache-error.
      IF ls_cache-error IS INITIAL.
        PERFORM read_name USING ls_cache-pernr
          CHANGING ls_cache-sap_name ls_cache-error.
      ENDIF.
      INSERT ls_cache INTO TABLE gt_cache.
    ENDIF.
    <data>-pernr = ls_cache-pernr.
    <data>-sap_name = ls_cache-sap_name.
    IF ls_cache-error IS NOT INITIAL.
      <data>-status = 'FEHLER'.
      PERFORM add_remark USING ls_cache-error CHANGING <data>-remark.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM read_name USING iv_pernr TYPE pernr_d
               CHANGING cv_name TYPE p0001-ename cv_error TYPE string.
  DATA lt_0001 TYPE STANDARD TABLE OF p0001.
  DATA lv_rc TYPE sy-subrc.
  CLEAR: cv_name, cv_error.
  CALL FUNCTION 'HR_READ_INFOTYPE'
    EXPORTING pernr = iv_pernr infty = '0001'
      begda = p_date endda = p_date bypass_buffer = 'X'
    IMPORTING subrc = lv_rc
    TABLES infty_tab = lt_0001
    EXCEPTIONS infty_not_found = 1 OTHERS = 2.
  IF sy-subrc <> 0 OR lv_rc <> 0.
    cv_error = 'IT0001 am Stichtag fehlt oder ist nicht berechtigt lesbar.'.
    RETURN.
  ENDIF.
  DELETE lt_0001 WHERE sprps <> space OR begda > p_date OR endda < p_date.
  IF lines( lt_0001 ) <> 1.
    cv_error = 'IT0001 am Stichtag fehlt oder ist nicht eindeutig.'.
    RETURN.
  ENDIF.
  READ TABLE lt_0001 INDEX 1 INTO DATA(ls_0001).
  cv_name = ls_0001-ename.
ENDFORM.

FORM add_remark USING iv_text TYPE string CHANGING cv_text TYPE string.
  IF cv_text IS INITIAL.
    cv_text = iv_text.
  ELSEIF iv_text IS NOT INITIAL.
    cv_text = |{ cv_text }; { iv_text }|.
  ENDIF.
ENDFORM.

FORM convert_amount USING iv_value TYPE string
                    CHANGING cv_amount TYPE maxbt cv_error TYPE string.
  DATA lv_amount TYPE decfloat34.
  DATA lv_rounded TYPE decfloat34.
  CONSTANTS lc_tolerance TYPE decfloat34 VALUE '0.00000001'.
  CLEAR: cv_amount, cv_error.
  FIND REGEX '^[+-]?[0-9]+([.][0-9]+)?([Ee][+-]?[0-9]+)?$'
    IN iv_value.
  IF sy-subrc <> 0.
    cv_error = |Betrag '{ iv_value }' fehlt/ungueltig; Dezimalpunkt erwartet.|.
    RETURN.
  ENDIF.
  TRY.
      lv_amount = iv_value.
      lv_rounded = round( val = lv_amount dec = 2 ).
      IF abs( lv_amount - lv_rounded ) > lc_tolerance.
        cv_error = |Betrag '{ iv_value }' enthaelt echte Bruchteile eines Cents.|.
        RETURN.
      ENDIF.
      cv_amount = lv_rounded.
      IF cv_amount <> lv_rounded.
        cv_error = 'Betrag nicht verlustfrei in MAXBT darstellbar.'.
      ENDIF.
    CATCH cx_root INTO DATA(lx_amount).
      cv_error = lx_amount->get_text( ).
  ENDTRY.
ENDFORM.

* Any matching IT0015 on this date blocks insertion, including locked records.
* Repeated under the employee lock immediately before HR_INFOTYPE_OPERATION.
FORM check_existing USING iv_pernr TYPE pernr_d
                    CHANGING cv_error TYPE string.
  DATA lt_0015 TYPE STANDARD TABLE OF p0015.
  DATA lv_rc TYPE sy-subrc.
  DATA lv_call_rc TYPE sy-subrc.
  CLEAR cv_error.
  CALL FUNCTION 'HR_READ_INFOTYPE'
    EXPORTING pernr = iv_pernr infty = '0015'
      begda = p_date endda = p_date bypass_buffer = 'X'
    IMPORTING subrc = lv_rc
    TABLES infty_tab = lt_0015
    EXCEPTIONS infty_not_found = 1 OTHERS = 2.
  lv_call_rc = sy-subrc.
  IF lv_call_rc <> 0.
    cv_error = |IT0015 technisch nicht lesbar: CALL-SUBRC={ lv_call_rc }, SUBRC={ lv_rc }.|.
    RETURN.
  ENDIF.
* Function-module SUBRC is distinct from the CALL FUNCTION SY-SUBRC.
* 0 = complete result, 8 = no records. Neither prevents a new insertion.
* 4 = partial authorization, 12 = no authorization: do not trust empty data.
  CASE lv_rc.
    WHEN 0 OR 8.
      " Continue with existence check; empty data is a normal result.
    WHEN 4 OR 12.
      cv_error = |IT0015: HR-Lesepruefung meldet eingeschraenkten Zugriff (SUBRC={ lv_rc }).|.
      RETURN.
    WHEN OTHERS.
      cv_error = |IT0015: Unerwarteter Rueckgabewert von HR_READ_INFOTYPE (SUBRC={ lv_rc }).|.
      RETURN.
  ENDCASE.
  LOOP AT lt_0015 TRANSPORTING NO FIELDS
    WHERE lgart = p_lgart AND begda <= p_date AND endda >= p_date.
    cv_error = |Lohnart { p_lgart } am { p_date DATE = USER } in IT0015 bereits vorhanden.|.
    RETURN.
  ENDLOOP.
ENDFORM.

FORM process_data.
  TYPES ty_t_indices TYPE STANDARD TABLE OF sy-tabix WITH DEFAULT KEY.
  TYPES: BEGIN OF ty_group,
           pernr TYPE pernr_d,
           amount TYPE decfloat34,
           has_error TYPE abap_bool,
           record TYPE ty_data,
           indices TYPE ty_t_indices,
         END OF ty_group.
  DATA lt_groups TYPE HASHED TABLE OF ty_group WITH UNIQUE KEY pernr.
  DATA lv_index TYPE sy-tabix.
  DATA lv_error TYPE string.
* Build exactly one posting group for each personnel number across all files.
* Keep source amounts and row order unchanged for the detailed ALV.
  LOOP AT gt_data ASSIGNING FIELD-SYMBOL(<data>).
    lv_index = sy-tabix.
    <data>-sap_amount = <data>-amount_trans.
    IF <data>-pernr IS INITIAL.
      CONTINUE.
    ENDIF.
    READ TABLE lt_groups ASSIGNING FIELD-SYMBOL(<group>)
      WITH TABLE KEY pernr = <data>-pernr.
    IF sy-subrc <> 0.
      INSERT VALUE #( pernr = <data>-pernr record = <data> )
        INTO TABLE lt_groups.
      READ TABLE lt_groups ASSIGNING <group>
        WITH TABLE KEY pernr = <data>-pernr.
    ENDIF.
    APPEND lv_index TO <group>-indices.
    <group>-amount = <group>-amount + <data>-amount_trans.
    IF <data>-status = 'FEHLER'.
      <group>-has_error = abap_true.
    ENDIF.
  ENDLOOP.

  LOOP AT lt_groups ASSIGNING <group>.
    CLEAR lv_error.
    IF <group>-has_error = abap_true.
      <group>-record-status = 'FEHLER'.
      <group>-record-remark =
        'Keine Gesamtbuchung: fehlerhafte Importzeile zu dieser Personalnummer.'.
    ELSE.
      TRY.
          <group>-record-sap_amount = <group>-amount.
          IF CONV decfloat34( <group>-record-sap_amount ) <> <group>-amount.
            lv_error = 'Gesamtbetrag nicht verlustfrei in MAXBT darstellbar.'.
          ENDIF.
        CATCH cx_root INTO DATA(lx_total).
          lv_error = lx_total->get_text( ).
      ENDTRY.
      IF lv_error IS NOT INITIAL.
        <group>-record-status = 'FEHLER'.
        <group>-record-remark = lv_error.
      ELSEIF <group>-record-sap_amount = 0.
        <group>-record-status = 'HINWEIS'.
        <group>-record-remark = 'Gesamtbetrag 0 EUR; keine Buchung.'.
      ELSEIF p_update = abap_true.
* One call per group; never call POST_RECORD for the constituent source rows.
        PERFORM post_record CHANGING <group>-record.
      ELSE.
        PERFORM check_existing USING <group>-pernr CHANGING lv_error.
        IF lv_error IS INITIAL.
          <group>-record-status = 'TEST'.
* ASCII-only source prevents UTF-8/ANSI double-encoding when copying to SAP.
          <group>-record-remark =
            |Pr{ cl_abap_conv_in_ce=>uccp( '00FC' ) }fung OK|.
        ELSE.
          <group>-record-status = 'FEHLER'.
          <group>-record-remark = lv_error.
        ENDIF.
      ENDIF.
    ENDIF.

* Copy the single group result back to every corresponding ALV detail row.
    LOOP AT <group>-indices INTO lv_index.
      READ TABLE gt_data ASSIGNING <data> INDEX lv_index.
      <data>-status = <group>-record-status.
      PERFORM add_remark USING <group>-record-remark CHANGING <data>-remark.
      IF <group>-record-status <> 'FEHLER' AND <data>-amount_trans = 0.
        <data>-status = 'HINWEIS'.
        PERFORM add_remark USING `Nullbetrag wird nicht gebucht.`
          CHANGING <data>-remark.
      ENDIF.
    ENDLOOP.
  ENDLOOP.
ENDFORM.

FORM post_record CHANGING cs_data TYPE ty_data.
  DATA ls_return TYPE bapireturn1.
  DATA ls_record TYPE p0015.
  DATA lv_locked TYPE abap_bool.
  DATA lv_error TYPE string.
  DATA lv_pernr TYPE pernr_d.
  DATA lt_attendees TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
  DATA lv_commit_rc TYPE sy-subrc.
  DATA lv_committed TYPE abap_bool.
  TRY.
      CALL FUNCTION 'BAPI_EMPLOYEE_ENQUEUE'
        EXPORTING number = cs_data-pernr
        IMPORTING return = ls_return
        EXCEPTIONS OTHERS = 1.
      IF sy-subrc <> 0 OR ls_return-type CA 'AEX'.
        lv_error = |Mitarbeitersperre fehlgeschlagen: { ls_return-message }|.
      ELSE.
        lv_locked = abap_true.
* Revalidate every distinct WDID contributing to the total under the lock.
        LOOP AT gt_data ASSIGNING FIELD-SYMBOL(<source>)
          WHERE pernr = cs_data-pernr.
          INSERT <source>-attendee_id INTO TABLE lt_attendees.
        ENDLOOP.
        LOOP AT lt_attendees INTO DATA(lv_attendee).
          PERFORM find_pernr USING lv_attendee CHANGING lv_pernr lv_error.
          IF lv_error IS INITIAL AND lv_pernr <> cs_data-pernr.
            lv_error = 'WDID-Zuordnung seit Vorpruefung geaendert.'.
          ENDIF.
          IF lv_error IS NOT INITIAL.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_error IS INITIAL.
          PERFORM check_existing USING cs_data-pernr CHANGING lv_error.
        ENDIF.
        IF lv_error IS INITIAL.
          ls_record-pernr = cs_data-pernr.
          ls_record-infty = '0015'.
          ls_record-subty = p_lgart.
          ls_record-lgart = p_lgart.
          ls_record-begda = p_date.
          ls_record-endda = p_date.
          ls_record-betrg = cs_data-sap_amount.
          ls_record-waers = gc_waers.
          CLEAR ls_return.
          CALL FUNCTION 'HR_INFOTYPE_OPERATION'
            EXPORTING infty = '0015' number = cs_data-pernr
              subtype = p_lgart validitybegin = p_date validityend = p_date
              record = ls_record
              operation = 'INS' tclas = 'A' dialog_mode = '0' nocommit = 'X'
            IMPORTING return = ls_return
            EXCEPTIONS OTHERS = 1.
          IF sy-subrc <> 0 OR ls_return-type CA 'AEX'.
            lv_error = |IT0015 fehlgeschlagen: { ls_return-message }|.
          ELSE.
            COMMIT WORK AND WAIT.
            lv_commit_rc = sy-subrc.
            IF lv_commit_rc = 0.
              lv_committed = abap_true.
              cs_data-status = 'GEBUCHT'.
              cs_data-remark =
                |IT0015 mit Gesamtbetrag { cs_data-sap_amount } EUR angelegt. { ls_return-message }|.
            ELSE.
              lv_error = 'Update fehlgeschlagen; SM13 und PA20 pruefen.'.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    CATCH cx_root INTO DATA(lx_post).
      lv_error = lx_post->get_text( ).
  ENDTRY.
  IF lv_error IS NOT INITIAL AND lv_committed = abap_false.
    ROLLBACK WORK.
    cs_data-status = 'FEHLER'.
    cs_data-remark = lv_error.
  ENDIF.
  IF lv_locked = abap_true.
    CALL FUNCTION 'BAPI_EMPLOYEE_DEQUEUE'
      EXPORTING number = cs_data-pernr
      EXCEPTIONS OTHERS = 1.
    IF sy-subrc <> 0.
      PERFORM add_remark USING `Warnung: Entsperren fehlgeschlagen (SM12).`
        CHANGING cs_data-remark.
    ENDIF.
  ENDIF.
  CALL FUNCTION 'HR_PSBUFFER_INITIALIZE' EXCEPTIONS OTHERS = 1.
ENDFORM.

FORM display_result.
  DATA lt_display TYPE ty_t_data.
  TYPES: BEGIN OF ty_total,
           pernr TYPE pernr_d,
           amount TYPE decfloat34,
           has_error TYPE abap_bool,
         END OF ty_total.
  DATA lt_totals TYPE HASHED TABLE OF ty_total WITH UNIQUE KEY pernr.
  DATA lo_alv TYPE REF TO cl_salv_table.
  DATA lo_layout TYPE REF TO cl_salv_layout.
  DATA ls_layout_key TYPE salv_s_layout_key.
  DATA lo_status_column TYPE REF TO cl_salv_column_table.
  DATA lo_table_column TYPE REF TO cl_salv_column_table.
  DATA lv_column TYPE salv_de_column.
  DATA lv_label TYPE scrtext_l.
* Sum transaction amounts per person after selection; errors take precedence.
  LOOP AT gt_data ASSIGNING FIELD-SYMBOL(<sum_data>)
    WHERE pernr IS NOT INITIAL.
    READ TABLE lt_totals ASSIGNING FIELD-SYMBOL(<total>)
      WITH TABLE KEY pernr = <sum_data>-pernr.
    IF sy-subrc <> 0.
      INSERT VALUE #( pernr = <sum_data>-pernr ) INTO TABLE lt_totals.
      READ TABLE lt_totals ASSIGNING <total>
        WITH TABLE KEY pernr = <sum_data>-pernr.
    ENDIF.
    <total>-amount = <total>-amount + <sum_data>-amount_trans.
    IF <sum_data>-status = 'FEHLER'.
      <total>-has_error = abap_true.
    ENDIF.
  ENDLOOP.
  LOOP AT gt_data ASSIGNING FIELD-SYMBOL(<data>).
    <data>-status_icon = '@09@'. " Default: yellow, including exactly EUR 50
    IF <data>-status = 'FEHLER'.
      <data>-status_icon = '@0A@'. " Red light
    ELSEIF <data>-pernr IS NOT INITIAL.
      READ TABLE lt_totals ASSIGNING <total>
        WITH TABLE KEY pernr = <data>-pernr.
      IF sy-subrc = 0.
        IF <total>-has_error = abap_true.
          <data>-status_icon = '@0A@'.
        ELSEIF <total>-amount > 50.
          <data>-status_icon = '@08@'.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.
* Display option only: preserve all import/error rows in GT_DATA.
  lt_display = gt_data.
  IF p_hide = abap_true.
    DELETE lt_display WHERE pernr IS INITIAL.
  ENDIF.
  IF lt_display IS INITIAL.
    MESSAGE 'Keine anzuzeigenden Saetze; ggf. Ausblendung ohne PerNr deaktivieren.'
      TYPE 'S'.
    RETURN.
  ENDIF.
  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv CHANGING t_table = lt_display ).
      DATA(lo_columns) = lo_alv->get_columns( ).
      lo_columns->set_optimize( abap_true ).
      DATA(lo_descr) = CAST cl_abap_structdescr(
        cl_abap_typedescr=>describe_by_data( VALUE ty_data( ) ) ).
      LOOP AT lo_descr->components INTO DATA(ls_component).
        lv_column = ls_component-name.
        CLEAR lv_label.
        IF sy-tabix >= 2 AND sy-tabix <= 20.
          DATA(lv_index) = sy-tabix - 1.
          READ TABLE gt_headers INDEX lv_index INTO DATA(lv_header).
          lv_label = lv_header.
        ELSE.
          CASE lv_column.
            WHEN 'FILENAME'.   lv_label = 'Dateiname'.
            WHEN 'PERNR'.      lv_label = 'SAP-Personalnummer'.
            WHEN 'SAP_NAME'.   lv_label = 'Name aus IT0001 (ENAME)'.
            WHEN 'EXCEL_ROW'.  lv_label = 'Excel-Zeile'.
            WHEN 'SAP_AMOUNT'. lv_label = 'Betrag IT0015'.
            WHEN 'STATUS_ICON'. lv_label = 'Status'.
            WHEN 'STATUS'.     lv_label = 'Statustext'.
            WHEN 'REMARK'.     lv_label = 'Bemerkung / Fehler / Warnungen'.
          ENDCASE.
        ENDIF.
        DATA(lo_column) = lo_columns->get_column( lv_column ).
        lo_table_column ?= lo_column.
        lo_table_column->set_key( abap_false ).
        lo_column->set_short_text( CONV scrtext_s( lv_label ) ).
        lo_column->set_medium_text( CONV scrtext_m( lv_label ) ).
        lo_column->set_long_text( lv_label ).
* Default ALV view: hide filename through payment date and report through date.
* Source fields remain in GT_DATA and can be shown via the column selection.
        CASE lv_column.
          WHEN 'FILENAME' OR 'COMPANY_CODE' OR 'COMPANY_NAME' OR
               'GROUP_ID' OR 'PAYMENT_DATE' OR 'REPORT_KEY' OR
               'REPORT_ID' OR 'EXPENSE_SUBTYPE' OR
               'ENTRY_KEY' OR 'TRANSACTION_DT' OR 'TRIP_PURPOSE' OR
               'VENDOR' OR 'ATTENDEE_COUNT' OR 'EXCEL_ROW' OR
               'SAP_AMOUNT' OR 'STATUS'.
            lo_column->set_visible( abap_false ).
        ENDCASE.
      ENDLOOP.
* Fixed display width only: full comments remain in the internal table.
      lo_columns->get_column( 'COMMENTS' )->set_optimized( abap_false ).
      lo_columns->get_column( 'COMMENTS' )->set_output_length( 40 ).
      lo_status_column ?= lo_columns->get_column( 'STATUS_ICON' ).
      lo_status_column->set_icon( abap_true ).
      lo_status_column->set_optimized( abap_false ).
      lo_status_column->set_output_length( 6 ).
      lo_columns->set_column_position(
        columnname = 'STATUS_ICON' position = 1 ).
      lo_columns->set_column_position(
        columnname = 'PERNR' position = 2 ).
      lo_columns->set_column_position(
        columnname = 'SAP_NAME' position = 3 ).
* Freeze exactly the first three columns when scrolling horizontally.
      lo_status_column->set_key( abap_true ).
      lo_table_column ?= lo_columns->get_column( 'PERNR' ).
      lo_table_column->set_key( abap_true ).
      lo_table_column ?= lo_columns->get_column( 'SAP_NAME' ).
      lo_table_column->set_key( abap_true ).
      lo_columns->set_key_fixation( abap_true ).
      lo_alv->get_aggregations( )->add_aggregation(
        columnname = 'AMOUNT_TRANS'
        aggregation = if_salv_c_aggregation=>total ).
      lo_alv->get_aggregations( )->add_aggregation(
        columnname = 'AMOUNT_REIMB'
        aggregation = if_salv_c_aggregation=>total ).
      lo_alv->get_sorts( )->add_sort(
        columnname = 'PERNR'
        sequence = if_salv_c_sort=>sort_up
        subtotal = abap_true ).
      lo_alv->get_functions( )->set_all( abap_true ).
* Persist layouts per report; allow user-specific and global layouts.
* Apply the selected layout after configuring the program's default view.
      lo_layout = lo_alv->get_layout( ).
      ls_layout_key-report = sy-repid.
      lo_layout->set_key( ls_layout_key ).
      lo_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).
      lo_layout->set_default( abap_true ).
      IF p_layout IS NOT INITIAL.
        lo_layout->set_initial_layout( p_layout ).
      ENDIF.
      lo_alv->get_display_settings( )->set_list_header(
        CONV lvc_title( |Einlesen Concur { p_date DATE = USER }| ) ).
      lo_alv->display( ).
    CATCH cx_root INTO DATA(lx_alv).
      DATA(lv_error) = lx_alv->get_text( ).
      MESSAGE lv_error TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.
