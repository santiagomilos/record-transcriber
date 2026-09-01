# Product Mission

## Problem

Meeting recordings and voice notes pile up as audio and video files that nobody can search, skim, or quote from. Getting to the text means either listening to the whole thing again or handing the recording to a paid service — which charges by the hour and requires uploading private conversations to a third party. For recordings that are internal, confidential, or simply personal, that upload is the part that makes the tooling unusable.

## Target Users

A single person transcribing their own recordings: meetings, interviews, and voice notes, mostly in Spanish with occasional English. Low volume, no team workflow, no multi-tenant concerns. The user is comfortable in a terminal and installs tools with Homebrew.

## Solution

A Go command-line tool that runs the whole pipeline locally. It accepts any audio or video file, normalizes it with ffmpeg, and transcribes it with whisper.cpp using the `large-v3-turbo` model — around 3% word error rate on Spanish, and 9–18x faster than real time on Apple Silicon.

Three properties follow from running locally that a hosted service cannot offer: the audio never leaves the machine, there is no per-hour cost, and there is no upload size limit.

The transcript is written as plain text and as subtitles (SRT and VTT) with timestamps. From there the tool can pass the transcript to Claude to produce a summary or a structured meeting minute, so the recording becomes something you can act on rather than just something you can read.
