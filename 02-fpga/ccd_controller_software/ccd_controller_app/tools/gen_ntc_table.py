#!/usr/bin/env python3
"""
Generate src/app_logic/ntc_tables.h (NTC code -> temperature lookup tables).

Parses the NTC_* macros from src/include/board_config.h (single source of truth),
computes the code->temperature table for the sensor (AIN0) and environment (AIN3)
channels, and emits a GENERATED C header.

Both channels use the divider topology:
    Vref - R1 - (tap) - R2 - Rntc - GND
    V = Vref * (R2 + Rntc) / (R1 + R2 + Rntc),   code = V / FS * 32768

Usage (run from anywhere):
    python tools/gen_ntc_table.py
"""

import os
import re
import math

ADC_FS_VOLT = 4.096     # ads1118 PGA full scale (+/-4.096V), matches ADS1118_FS_VOLT
T0_K = 273.15           # 0 degC in kelvin
T25_K = 298.15          # 25 degC in kelvin
T_START = -50           # degC
T_END = 151             # degC (exclusive)
T_STEP = 1              # degC

HERE = os.path.dirname(os.path.abspath(__file__))
BOARD_CONFIG = os.path.join(HERE, '..', 'src', 'include', 'board_config.h')
OUT_HEADER = os.path.join(HERE, '..', 'src', 'app_logic', 'ntc_tables.h')

MACRO_RE = re.compile(r'#define\s+(NTC_[A-Z0-9_]+)\s+([0-9]+(?:\.[0-9]+)?)f?\s*/\*')


def parse_macros(path):
    """Extract NTC_* macros (name -> float) from board_config.h."""
    vals = {}
    with open(path, 'r', encoding='utf-8') as f:
        for m in MACRO_RE.finditer(f.read()):
            vals[m.group(1)] = float(m.group(2))
    return vals


def ntc_res(t_c, r25, beta):
    """NTC resistance (ohm) at t_c degC via the B-equation."""
    tk = t_c + T0_K
    return r25 * math.exp(beta * (1.0 / tk - 1.0 / T25_K))


def adc_code(t_c, r1, r2, r25, beta, vref):
    """ADC code for temperature t_c with the Vref-R1-R2-Rntc-GND divider."""
    rntc = ntc_res(t_c, r25, beta)
    v = vref * (r2 + rntc) / (r1 + r2 + rntc)
    return int(round(v / ADC_FS_VOLT * 32768.0))


def build_table(prefix, vals):
    """Ascending-code table of (code, temp_x10) for the given channel prefix."""
    r1 = vals[prefix + '_R1_OHM']
    r2 = vals[prefix + '_R2_OHM']
    r25 = vals[prefix + '_R25_OHM']
    beta = int(vals[prefix + '_BETA'])
    vref = vals[prefix + '_DIV_VREF_V']

    points = [(adc_code(t, r1, r2, r25, beta, vref), t * 10)
              for t in range(T_START, T_END, T_STEP)]
    points.sort(key=lambda p: p[0])

    # drop zero-width code segments (identical rounded codes), keep the hottest
    dedup = []
    for code, t10 in points:
        if not dedup or code != dedup[-1][0]:
            dedup.append((code, t10))
    return dedup, r1, r2, r25, beta, vref


def fmt_points(points):
    """Format (code, temp_x10) pairs as C initializers, 6 per line."""
    lines = []
    for i in range(0, len(points), 6):
        row = ', '.join('{%4d, %4d}' % p for p in points[i:i + 6])
        lines.append('    ' + row + (',' if i + 6 < len(points) else ''))
    return '\n'.join(lines)


def emit_table(name, points):
    out = []
    out.append('static const NtcPoint %s[] = {' % name)
    out.append(fmt_points(points))
    out.append('};')
    out.append('#define %s_N  (sizeof %s / sizeof %s[0])'
               % (name.upper().replace('G_', ''), name, name))
    return '\n'.join(out)


def main():
    vals = parse_macros(BOARD_CONFIG)
    missing = [p for p in ('SENSOR', 'ENV')
               for k in ('_R1_OHM', '_R2_OHM', '_R25_OHM', '_BETA', '_DIV_VREF_V')
               if 'NTC_' + p + k not in vals]
    if missing:
        sys.exit('missing macros in %s: %s' % (BOARD_CONFIG, ', '.join(missing)))

    sensor, s_r1, s_r2, s_r25, s_beta, s_vref = build_table('NTC_SENSOR', vals)
    env, e_r1, e_r2, e_r25, e_beta, e_vref = build_table('NTC_ENV', vals)

    params = (
        '#ifndef NTC_TABLES_H\n'
        '#define NTC_TABLES_H\n'
        '\n'
        '#include "xil_types.h"\n'
        '\n'
        '#ifdef __cplusplus\n'
        'extern "C" {\n'
        '#endif\n'
        '\n'
        'typedef struct {\n'
        '    u16 Code;\n'
        '    s16 TempX10;      /* temperature x10 (degC) */\n'
        '} NtcPoint;\n'
        '\n'
        '/* sensor (AIN0): R1=%g R2=%g R25=%g B=%d Vref=%gV, topology Vref-R1-R2-Rntc-GND */\n'
        'static const NtcPoint g_sensor_ntc_table[] = {\n'
        '%s\n'
        '};\n'
        '#define NTC_SENSOR_TABLE_N  (sizeof g_sensor_ntc_table / sizeof g_sensor_ntc_table[0])\n'
        '\n'
        '/* environment (AIN3): R1=%g R2=%g R25=%g B=%d Vref=%gV, topology Vref-R1-R2-Rntc-GND */\n'
        'static const NtcPoint g_env_ntc_table[] = {\n'
        '%s\n'
        '};\n'
        '#define NTC_ENV_TABLE_N  (sizeof g_env_ntc_table / sizeof g_env_ntc_table[0])\n'
        '\n'
        '#ifdef __cplusplus\n'
        '}\n'
        '#endif\n'
        '\n'
        '#endif /* NTC_TABLES_H */\n'
    )

    header = (
        '/******************************************************************************\n'
        '* @file ntc_tables.h\n'
        '*\n'
        '* GENERATED FILE - do not edit by hand.\n'
        '* Regenerate with: python tools/gen_ntc_table.py\n'
        '*\n'
        '* NTC code -> temperature (x10 degC) lookup tables for the sensor (AIN0) and\n'
        '* environment (AIN3) channels. Each table is sorted by ascending code and is\n'
        '* interpolated linearly at runtime (see app_logic/ntc.c).\n'
        '* Divider topology: Vref - R1 - (tap) - R2 - Rntc - GND\n'
        '*   V = Vref*(R2+Rntc)/(R1+R2+Rntc),  code = V/FS*32768 with FS=%.3fV\n'
        '* Parameters come from board_config.h.\n'
        '*\n'
        '* @note <pre>\n'
        '* MODIFICATION HISTORY:\n'
        '*\n'
        '* Ver   Who  Date     Changes\n'
        '* ----- ---- -------- -----------------------------------------------\n'
        '* 1.0   gen  26/08/03 Generated from board_config.h placeholder constants\n'
        '* </pre>\n'
        '******************************************************************************/\n'
        '\n'
    ) % (ADC_FS_VOLT,)

    with open(OUT_HEADER, 'w', encoding='utf-8', newline='\n') as f:
        f.write(header + params % (s_r1, s_r2, s_r25, s_beta, s_vref,
                                   fmt_points(sensor),
                                   e_r1, e_r2, e_r25, e_beta, e_vref,
                                   fmt_points(env)))

    # self-check: report a few known mapping points
    print('wrote %s' % os.path.normpath(OUT_HEADER))
    print('sensor table: %d points, code range %d..%d'
          % (len(sensor), sensor[0][0], sensor[-1][0]))
    print('env    table: %d points, code range %d..%d'
          % (len(env), env[0][0], env[-1][0]))
    for t in (-50, 0, 25, 80, 150):
        c = adc_code(t, s_r1, s_r2, s_r25, s_beta, s_vref)
        print('  %4d degC -> code %5d' % (t, c))


if __name__ == '__main__':
    main()
