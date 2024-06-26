#!/bin/env nu

use std log

const PRJ_NAME = "pic_programmer" # TODO: Change
# const PRJ_DIR = ""

def setup-output-dir [] {
    let output_prefix = ($env | get -i OUTPUT_PREFIX | default 'fab')
    let output_dir = "outputs" | path join $"($output_prefix)_(date now | format date "%Y-%m-%dT%H:%M:%S")"
    mkdir $output_dir
    $output_dir
}

def with-stage [
    stage: string
] {
    $in | insert stage { $stage }
}

# Run electrial rules checker
export def erc [
    output_dir: path
] {
    ^find ($PRJ_NAME) -type f -name "*.kicad_sch" 
        | lines 
        | each { |fname| 
            let sheet_name = ($fname | path parse | get stem)
            let output_fname = ($output_dir | path join $"erc_($sheet_name).json")
            kicad-cli sch erc $fname --format json --output $output_fname 
                | complete 
                | merge (open $output_fname 
                    | get sheets.violations 
                    | each { |row| $row | get -i severity | default 0 | uniq --count } 
                    | flatten 
                    | transpose --ignore-titles --header-row
                    | into record
                )
                | merge { output_fname: $output_fname }
        }
        | with-stage "erc"
        | default 0 warning
        | default 0 error
}

# Run design rules checker
export def drc [
    output_dir: path
] {
    let output_fname = ($output_dir | path join $"drc.json")
    ^find ($PRJ_NAME) -type f -name "*.kicad_pcb" 
        | lines 
        | each { |fname| 
            kicad-cli pcb drc $fname --format json --output $output_fname 
                | complete 
                | merge (open $output_fname 
                    | get violations 
                    | each { |row| $row | get -i severity | default 0 | uniq --count } 
                    | flatten 
                    | transpose --ignore-titles --header-row
                    | into record
                )
                | merge { output_fname: $output_fname }
        }
        | with-stage "drc"
        | default 0 warning
        | default 0 error
}

# Generate gerbers
# FIXME: Needs to act on correct pcb filename - too tired
export def gerbers [
    output_dir: path
] {
    kicad-cli pcb export gerbers $PRJ_NAME --no-protel-ext -o ([$output_dir, "gerbers"] | path join)
        | complete
        | with-stage "gerbers"
}

# Generate drill files
# FIXME: Needs to act on correct pcb filename - too tired
export def drill [
    output_dir: path
] {
    kicad-cli pcb export drill --map-format gerberx2 --generate-map --format gerber ([$output_dir, "gerbers"] | path join)
        | complete
        | with-stage "drill"
}

# Test design
export def test [
    --fail-on-warning # Fail if warnings present
] -> bool {
    let output_dir = (setup-output-dir)

    let erc_output = (erc $output_dir)
    let drc_output = (drc $output_dir)

    let test_output = ([$erc_output, $drc_output] | flatten)
    let test_output_path = ([$output_dir, "test-log.json"] | path join)
    $test_output | to json | save $test_output_path

    log info $"Test file output: ($test_output_path)"

    let sums  = (open $test_output_path | select error warning | math sum)
    not (($sums.error > 0) or (($fail_on_warning) and ($sums.warning > 0)))
}

# Generate fab files
export def gen-fab [] {
    let output_dir = (setup-output-dir)

    let gerbers_output = (gerbers $output_dir)
    let drill_output = (drill $output_dir)

    let gen_fab_output = ([$gerbers_output, $drill_output] | flatten)
    let gen_fab_output_path = ([$output_dir, "gen-fab-log.json"] | path join)
    $gen_fab_output | to json | save $gen_fab_output_path

    log info $"Fab generation file output: ($gen_fab_output_path)"
}

export def main [] {}