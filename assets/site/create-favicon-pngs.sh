#!/usr/bin/env sh

inkscape --batch-process --export-type=png --export-width=48 --export-height=48 --export-filename=favicon-48.png favicon.svg
inkscape --batch-process --export-type=png --export-width=32 --export-height=32 --export-filename=favicon-32.png favicon.svg
inkscape --batch-process --export-type=png --export-width=16 --export-height=16 --export-filename=favicon-16.png favicon.svg
