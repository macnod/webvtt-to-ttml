# webvtt-to-ttml

## Overview

The webvtt-to-ttml program converts one or more WebVTT files into a single, multi-language TTML file.

Here are some ways to run it:

### Example 1

The following command will display detailed help on the program's options:

    webvtt-to-ttml --help

### Example 2

The following will parse and merge abc-english.vtt and abc-arabic.vtt,
then assemble a single TTML file and write it to disk with the
filename "abc.ttml".

    webvtt-to-ttml -i abc-english.vtt:eng,abc-arabic.vtt:ara -o abc.ttml -t "ABC"


## Options

    --input, -i value

Required.  The file names of the input WebVTT files, together with the language of each file. Use the format -i filename:language,filename:language. For example: abc-english.webvtt:en,abc-arabic.webvtt:ar. You can specify the language in ISO-639-2 (3 characters), ISO-639-3 (3 characters), or ISO-639-1 (2 characters), but if you specify a 3-character language code, this program will convert it into a 2-character language code for use in the target TTML file. The file or files you specify here will all be rendered as a single TTML file; that format supports multiple languages in a single file. The target TTML file will have the name you specify with the --output option.

    --output, -o value

Required.  The file name to which you want to write the resulting TTML. See the --force option if you want to overwrite an existing TTML file.

    --title, -t value

Required.  The title of the video that the input caption files belong to.

    --force, -f

Optional.  Normally, this program halts if the output TTML file already exists. Use this option if you want the program to overwrite the output file when it already exists.

    --help

Optional. Show this nice documentation.

    --limit, -l value

Optional.  Defaults to '0'.  This option allows you to limit the number of caption records to process. If you don't provide a value for this option, then the entire input file is processed. Otherwise, processing stops after the number of records you specify here.
