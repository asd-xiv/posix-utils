#!/bin/sh

# The primitives of get-youtube-transcript that make no request. The script
# sources this file, and so does each test file. This file sources nothing and
# sets no shell options.

# parse_video_id <video>
#
# Print the video id of <video>: a bare id, a youtu.be/<id> URL, or a
# youtube.com URL of the shapes /watch?v=<id>, /shorts/<id>, /embed/<id> and
# /live/<id>. The scheme, "www." and "m." are optional. An id is 11 characters
# of A-Za-z0-9_-.
#
# RETURNS
#   1   <video> has none of these shapes
parse_video_id() {
  parse_rest=$(printf '%s' "$1" \
    | sed -e 's|^[Hh][Tt][Tt][Pp][Ss]\{0,1\}://||' -e 's|^www\.||' -e 's|^m\.||')

  case "$parse_rest" in
    youtu.be/*)
      parse_id=${parse_rest#youtu.be/}
      parse_id=${parse_id%%[?&#/]*}
      ;;
    youtube.com/shorts/* | youtube.com/embed/* | youtube.com/live/*)
      # The id ends at the first ?, &, # or / of the rest
      parse_id=${parse_rest#youtube.com/*/}
      parse_id=${parse_id%%[?&#/]*}
      ;;
    youtube.com/watch\?*)
      # Drop the fragment, split on &, take the first v=
      parse_id=$(printf '%s' "${parse_rest#*\?}" \
        | sed 's/#.*//' | tr '&' '\n' | sed -n 's/^v=//p' | head -n 1)
      ;;
    *) parse_id=$parse_rest ;;
  esac

  case "$parse_id" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  [ "${#parse_id}" -eq 11 ] || return 1

  printf '%s' "$parse_id"
}

# find_track_url <player-file> <lang>
#
# Print the baseUrl of the best caption track for <lang> in <player-file>. A
# track matches when its languageCode is <lang> or starts with "<lang>-". A
# manual track comes before an auto-generated one, then an exact code before a
# longer one.
#
# RETURNS
#   1   No track matches
find_track_url() {
  find_url=$(jq -r --arg lang "$2" '
    [
      (.captions.playerCaptionsTracklistRenderer.captionTracks // [])[]
      | select(
        .languageCode == $lang
        or (.languageCode | startswith($lang + "-"))
      )
      | . + {
        rank: (
          (if .kind == "asr" then 2 else 0 end)
          + (if .languageCode == $lang then 0 else 1 end)
        )
      }
    ]
    | sort_by(.rank)
    | (.[0].baseUrl // empty)' "$1")

  [ -n "$find_url" ] || return 1
  printf '%s' "$find_url"
}

# print_transcript <captions-file> <format>
#
# Print a json3 <captions-file> in <format>:
#
#   text            One caption per line, text only
#   clipped-jsonl   One caption per line as JSON: startMs, endMs, text
#   original-jsonl  One event per line as JSON, as YouTube sends it
#
# A caption is an event with text. The text and clipped-jsonl formats skip the
# other events: the window set-up events, and the events marked aAppend that
# an auto-generated track carries. Both formats turn a newline inside a caption
# into a space and remove the spaces at its two ends. Both skip a caption that
# is then empty.
#
# YouTube sends the start and the duration of each caption. It does not send
# the end. An auto-generated caption stays on screen after the next one
# starts, so the two overlap. A manual caption ends before the next one
# starts. In clipped-jsonl, endMs is the smaller of start plus duration and
# the start of the next caption. The rule leaves a manual track unchanged and
# stops an auto-generated caption where the next one starts. The last caption
# ends at start plus duration.
#
# RETURNS
#   1   <format> is none of these, nothing printed
print_transcript() {
  case "$2" in
    text)
      jq -r '
        .events[]
        | select(.segs and (.aAppend != 1))
        | .segs
        | map(.utf8)
        | join("")
        | gsub("\n"; " ")
        | gsub("^ +| +$"; "")
        | select(. != "")
      ' "$1"
      ;;
    clipped-jsonl)
      jq -c '
        [
          .events[]
          | select(.segs and (.aAppend != 1))
          | {
            startMs: (.tStartMs // 0),
            shownUntilMs: ((.tStartMs // 0) + (.dDurationMs // 0)),
            text: (.segs | map(.utf8) | join("") | gsub("\n"; " ") | gsub("^ +| +$"; ""))
          }
          | select(.text != "")
        ] as $captions
        | range(0; $captions | length) as $i
        | $captions[$i]
        | {
          startMs,
          endMs: ([.shownUntilMs, ($captions[$i + 1].startMs // .shownUntilMs)] | min),
          text
        }
      ' "$1"
      ;;
    original-jsonl)
      jq -c '.events[]' "$1"
      ;;
    *) return 1 ;;
  esac
}
