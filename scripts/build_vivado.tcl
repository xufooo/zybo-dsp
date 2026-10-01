# SPDX-License-Identifier: GPL-2.0-only


set force 0
if {[lsearch -exact $argv "-force"] >= 0 || [lsearch -exact $argv "force"] >= 0} {
    set force 1
    puts "== -force: rerun synthesis + implementation =="
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ..]]
set build_dir  [file join $repo_root build fpga]
set proj_dir   [file join $build_dir zybo_audio.xpr]   ;
set xpr        [file join $proj_dir zybo_audio.xpr]

proc ip_source_signature {ip_dir} {
    set flist [list]
    foreach pat {hdl/*.v hdl/*.vhd hdl/adi_common/*.vhd component.xml xgui/*.tcl} {
        foreach f [lsort [glob -nocomplain "$ip_dir/$pat"]] {
            lappend flist "[file tail $f]:[file size $f]:[file mtime $f]"
        }
    }
    return [join $flist ";"]
}

set ip_dir   [file join $repo_root build ip digilent ip axi_i2s_adi_1.2]
set sig_file [file join $build_dir .ip_src_sig]
set sig_cur  [ip_source_signature $ip_dir]
if {[file exists $build_dir]} {
    set sig_old ""
    if {[file exists $sig_file]} {
        set fh [open $sig_file r]; set sig_old [string trim [read $fh]]; close $fh
    }
    if {$sig_old ne $sig_cur} {
        puts "== vendor IP sources changed (or no fingerprint) -> delete build/fpga and regenerate BD =="
        puts "   (else Vivado reuses the stale ipshared copy: edits would have no effect)"
        file delete -force $build_dir
    }
}
file mkdir $build_dir
set fh [open $sig_file w]; puts $fh $sig_cur; close $fh

if {[file exists $xpr]} {
    puts "== Opening existing project: $xpr =="
    open_project $xpr
    set_property XPM_LIBRARIES {XPM_MEMORY XPM_FIFO XPM_CDC} [current_project]
} else {
    puts "== Creating project + BD (build_bd.tcl) =="
    source [file join $script_dir build_bd.tcl]
}

puts "== Synthesis =="
if {$force || [get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    reset_run synth_1
    foreach r [get_runs *_synth_1] {
        set st [get_property STATUS $r]
        if {[string match "*ERROR*" $st] || $st in {"Aborted" "Failed"}} {
            puts "== resetting stale failed OOC run $r ($st) =="
            reset_run $r
        }
    }
    launch_runs synth_1 -jobs 2
    wait_on_run synth_1
    if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
        puts "ERROR: synthesis failed"; exit 1
    }
}

puts "== Implementation + Bitstream =="
set impl_st [get_property STATUS [get_runs impl_1]]
if {$force || $impl_st ni {"route_design Complete!" "write_bitstream Complete!"}} {
    for {set attempt 1} {$attempt <= 2} {incr attempt} {
        if {$attempt > 1} {
            puts "== Implementation attempt $attempt (previous failed: $impl_st), reset_run and rerun =="
            reset_run impl_1
        }
        if {[catch {launch_runs impl_1 -to_step write_bitstream -jobs 2} err]} {
            puts "WARN: launch_runs impl_1 failed: $err"
        }
        if {[catch {wait_on_run impl_1} err]} {
            puts "WARN: wait_on_run impl_1 failed: $err"
        }
        set impl_st [get_property STATUS [get_runs impl_1]]
        if {$impl_st in {"route_design Complete!" "write_bitstream Complete!"}} break
    }
}
if {$impl_st ni {"route_design Complete!" "write_bitstream Complete!"}} {
    puts "ERROR: implementation failed (status=$impl_st)"; exit 1
}
set bit_file [file join $proj_dir zybo_audio.runs impl_1 zybo_audio_wrapper.bit]
if {![file exists $bit_file]} {
    puts "ERROR: bitstream not generated: $bit_file"; exit 1
}

puts "== Export hardware platform (.xsa) =="
write_hw_platform -fixed -include_bit -force -file [file join $build_dir zybo_audio.xsa]

puts "\n== BUILD COMPLETE =="
puts "  bit:  $bit_file"
puts "  xsa:  [file join $build_dir zybo_audio.xsa]"
puts "  next: Linux side (linux/buildroot/buildroot_setup.sh) needs BOOT.BIN (fsbl+bit+u-boot)"
