#!/usr/bin/env python3
"""
Generate Plymouth script with explicit frame loading.
Plymouth script language doesn't support string formatting or loops,
so we generate the script with all frame loads hardcoded.

This generator produces the SAME style as the deployed des.script:
  - Static frames[] array with Image() calls
  - Single refresh_callback with elapsed_time accumulation
  - Plymouth API limitation comment

Usage:
    python3 generate_script.py [frame_count] [fps]
    python3 generate_script.py              # defaults: 180 30
    python3 generate_script.py 140 20
"""

import sys


def generate_plymouth_script(frame_count=180, fps=30, start_offset_frames=0):
    duration = frame_count / fps

    lines = []
    lines.append(f'# DES Cockpit Plymouth Boot Animation Script')
    lines.append(f'# Boot animation: {frame_count} frames @ {fps}fps = {duration:.1f}s')
    lines.append(f'# Auto-generated - do not edit manually')
    lines.append(f'# Regenerate with: cd recipes-core/plymouth && python3 generate_script.py {frame_count} {fps}')
    lines.append('')
    lines.append(f'frame_count = {frame_count};')
    lines.append(f'animation_fps = {fps};')
    lines.append('')
    lines.append('# Load all frames')
    lines.append('frames = [];')
    lines.append('')

    for i in range(frame_count):
        lines.append(f'frames[{i}] = Image("frame_{i:04d}.png");')

    lines.append('')
    lines.append('# Animation setup')
    lines.append('animation_sprite = Sprite();')
    lines.append('screen_width = Window.GetWidth();')
    lines.append('screen_height = Window.GetHeight();')
    lines.append('')
    lines.append('# NOTE: Plymouth\'s script engine does not expose wall-clock time.')
    lines.append('# The refresh callback is called at approximately 50 Hz (~20 ms).')
    lines.append('# We use a fixed +0.02 increment which is the standard approach')
    lines.append('# for Plymouth themes.  If the actual refresh rate differs, the')
    lines.append('# playback speed will shift proportionally \u2014 this is a known')
    lines.append('# limitation of the Plymouth script API.')
    lines.append('elapsed_time = 0;')
    lines.append(f'start_frame_offset = {start_offset_frames}; # {start_offset_frames / fps:.1f}s @ {fps}fps')
    lines.append('')
    lines.append('fun refresh_callback() {')
    lines.append('    target_frame = Math.Int(elapsed_time * animation_fps);')
    lines.append('    source_frame = target_frame + start_frame_offset;')
    lines.append('    if (source_frame >= frame_count)')
    lines.append('        current_frame_index = frame_count - 1;')
    lines.append('    else')
    lines.append('        current_frame_index = source_frame;')
    lines.append('')
    lines.append('    animation_sprite.SetImage(frames[current_frame_index]);')
    lines.append('')
    lines.append('    # Center sprite')
    lines.append('    frame_width = frames[current_frame_index].GetWidth();')
    lines.append('    frame_height = frames[current_frame_index].GetHeight();')
    lines.append('    pos_x = (screen_width - frame_width) / 2;')
    lines.append('    pos_y = (screen_height - frame_height) / 2;')
    lines.append('    animation_sprite.SetPosition(pos_x, pos_y, 100);')
    lines.append('')
    lines.append('    elapsed_time += 0.02;')
    lines.append('}')
    lines.append('')
    lines.append('Plymouth.SetRefreshFunction(refresh_callback);')
    lines.append('')
    lines.append('fun progress_callback(duration, progress) { }')
    lines.append('Plymouth.SetBootProgressFunction(progress_callback);')
    lines.append('')
    lines.append('fun message_callback(text) { }')
    lines.append('Plymouth.SetMessageFunction(message_callback);')
    lines.append('')
    lines.append('fun display_normal_callback() { }')
    lines.append('fun display_password_callback(prompt, bullets) { }')
    lines.append('fun display_question_callback(prompt, entry) { }')
    lines.append('')
    lines.append('Plymouth.SetDisplayNormalFunction(display_normal_callback);')
    lines.append('Plymouth.SetDisplayPasswordFunction(display_password_callback);')
    lines.append('Plymouth.SetDisplayQuestionFunction(display_question_callback);')
    lines.append('')
    lines.append('fun quit_callback() {')
    lines.append('    animation_sprite = NULL;')
    lines.append('}')
    lines.append('')
    lines.append('Plymouth.SetQuitFunction(quit_callback);')
    lines.append('')

    return '\n'.join(lines)


if __name__ == "__main__":
    fc = int(sys.argv[1]) if len(sys.argv) > 1 else 180
    fps = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    start_offset = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    script_content = generate_plymouth_script(
        frame_count=fc, fps=fps, start_offset_frames=start_offset
    )

    output_path = "plymouth/des-theme/des.script"
    with open(output_path, 'w') as f:
        f.write(script_content)

    dur = fc / fps
    print(f"Generated Plymouth script: {output_path}")
    print(f"  {fc} frames @ {fps}fps = {dur:.1f}s")
    print(f"  start offset: {start_offset} frame(s) = {start_offset / fps:.1f}s")
    print(f"  Script size: {len(script_content)} bytes")
