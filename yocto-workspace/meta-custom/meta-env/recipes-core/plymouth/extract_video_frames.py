#!/usr/bin/env python3
"""
Extract video frames for Plymouth boot animation.
Converts MP4 to PNG frame sequence using integer-domain sampling
to produce exactly the correct number of frames at the target FPS.
"""

import cv2
import os
import sys
import shutil


def extract_frames(video_path, output_dir, target_fps=30,
                   target_width=1024, target_height=600):
    """Extract frames from video at specified FPS and resolution.

    Uses integer-domain comparison to avoid floating-point drift:
        emit frame when (frame_num * target_fps) >= (output_num * src_fps)

    This guarantees identical output regardless of rounding behaviour.
    """

    # Open video
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"Error: Cannot open video {video_path}")
        return 0  # return count instead of bool

    # Get video properties
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    src_fps = cap.get(cv2.CAP_PROP_FPS)
    if src_fps <= 0:
        print("Error: Cannot determine source FPS")
        cap.release()
        return 0

    duration = total_frames / src_fps
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    expected_output = int(round(duration * target_fps))

    print(f"Video info:")
    print(f"  Resolution : {width}x{height} -> {target_width}x{target_height}")
    print(f"  Source FPS : {src_fps}")
    print(f"  Duration   : {duration:.2f}s")
    print(f"  Src frames : {total_frames}")
    print(f"  Target FPS : {target_fps}")
    print(f"  Expected   : {expected_output} output frames")
    print()

    # Safety guard: only delete if basename is "frames"
    if os.path.exists(output_dir):
        if os.path.basename(output_dir) != "frames":
            print(f"Error: refusing to delete '{output_dir}' — "
                  f"expected basename 'frames', got '{os.path.basename(output_dir)}'")
            cap.release()
            return 0
        shutil.rmtree(output_dir)
    os.makedirs(output_dir)

    # Integer-domain sampling:
    # Emit output frame N when the source frame index reaches or passes
    # the point (N / target_fps) seconds into the video.
    # Comparison in integer domain avoids all floating-point drift:
    #   frame_num * target_fps >= output_num * src_fps
    # We use round(src_fps) to keep integer math exact for common rates
    # (24, 25, 30, 60).
    src_fps_int = int(round(src_fps))

    frame_num = 0
    output_num = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Integer comparison: should we emit this frame?
        if frame_num * target_fps >= output_num * src_fps_int:
            resized = cv2.resize(frame, (target_width, target_height),
                                 interpolation=cv2.INTER_LANCZOS4)
            path = os.path.join(output_dir, f"frame_{output_num:04d}.png")
            cv2.imwrite(path, resized, [cv2.IMWRITE_PNG_COMPRESSION, 6])

            if output_num % 20 == 0:
                print(f"  frame {output_num:4d} (src #{frame_num})")

            output_num += 1

        frame_num += 1

    cap.release()

    actual_duration = output_num / target_fps if target_fps else 0
    print(f"\nDone! Extracted {output_num} frames to {output_dir}")
    print(f"  Resolution  : {target_width}x{target_height}")
    print(f"  Playback    : {output_num} frames @ {target_fps}fps = {actual_duration:.2f}s")

    return output_num


if __name__ == "__main__":
    # Use paths relative to this script's location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    video_path = os.path.join(script_dir, "ferrari_booting_video2.mp4")
    output_dir = os.path.join(script_dir, "plymouth", "des-theme", "frames")

    if not os.path.exists(video_path):
        print(f"Error: Video not found at {video_path}")
        sys.exit(1)

    # Extract at 1024x600 for RPi display.
    # target_fps=30 preserves original frame count for 30fps source video,
    # keeping playback duration identical to the source.
    count = extract_frames(video_path, output_dir, target_fps=30,
                           target_width=1024, target_height=600)

    # Frame count assertion: must match des.script / bbappend expectations
    EXPECTED_FRAMES = 180
    if count != EXPECTED_FRAMES:
        print(f"\nERROR: Expected {EXPECTED_FRAMES} frames but got {count}.")
        print("       Update des.script frame_count and bbappend range/seq,")
        print("       or investigate the source video.")
        sys.exit(1)

    print(f"\nVerified: {count} frames == {EXPECTED_FRAMES} expected. OK.")
    sys.exit(0)
