set hxRoot [file normalize [file join [file dirname [info script]] ..]]
set hxOut [file join $hxRoot build td]
file mkdir $hxOut
cd $hxOut
set hxHdl [file join $hxRoot lab_ex3_osd user_source hdl_source]
set hxIp [file join $hxRoot lab_ex3_osd user_source ip_source]
set hxProject [file join $hxOut camera_to_dsi_display.prj]
set hxPhase read_design
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    puts "HX_PROJECT=<$hxProject>"
    eval [list open_project $hxProject -single_run]
    load_run_param -run syn_1
    elaborate -top design_top_wrapper
    eval [list read_adc [file join $hxRoot lab_ex3_osd user_source constraints_source pin.adc]]
    eval [list read_ip_adc -ip ddr2 -file [file join $hxHdl ph1p35_ddr ddr2 src adc ddr2.adc]]
    eval [list read_sdc [file join $hxRoot lab_ex3_osd td_project camera_to_dsi_display.sdc]]
    eval [list read_sdc -ip ddr2 [file join $hxHdl ph1p35_ddr ddr2 src sdc ddr2.sdc]]
    eval [list read_sdc -ip w128_d512_fifo [file join $hxIp w128_d512_fifo w128_d512_fifo.tcl]]
    set hxPhase opt_rtl
    optimize_rtl
    report_area -file video_tracking_rtl.area
    export_db video_tracking_rtl.db
    set hxPhase opt_gate
    optimize_gate -packarea video_tracking_gate.area
    legalize_phy_inst
    update_timing
    report_timing_summary -file video_tracking_gate.timing
    export_db video_tracking_gate.db
    if {[info exists ::env(HX_VERIFY_STAGE)] && $::env(HX_VERIFY_STAGE) eq "syn"} {
        puts "HX_SYNTHESIS_PASS"
    } else {
        load_run_param -run phy_1
        set hxPhase place
        place
        update_timing -mode manhattan
        report_timing_summary -file video_tracking_place.timing
        report_area -io_info -file video_tracking_phy.area
        export_db video_tracking_place.db
        set hxPhase route
        route
        update_timing -mode final
        report_area -io_info -file video_tracking_phy.area
        report_timing_status -file video_tracking_phy.ts
        report_timing_summary -file video_tracking_pr.timing
        report_timing_exception -file video_tracking_exceptions.timing
        export_db video_tracking_pr.db
        set hxPhase bitgen
        bitgen -bit video_tracking.bit
        export_bitgen_param -file video_tracking_bitgen.f
        puts "HX_BUILD_PASS"
    }
} hxResult]} {
    puts stderr "HX_BUILD_FAILED hxPhase=$hxPhase: $hxResult"
    set hxF [open [file join $hxOut build_failure.txt] w]
    puts $hxF "hxPhase=$hxPhase\n$hxResult"
    close $hxF
    exit 1
}
exit 0



