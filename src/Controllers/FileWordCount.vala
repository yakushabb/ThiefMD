/*
 * Copyright (C) 2018-2024 M.W. Freed
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

namespace ThiefMD.Controllers.FileWordCount {

    public int get_word_count_from_string (string text) {
        int word_count = 0;
        bool in_yaml = false;
        bool in_code_block = false;
        bool in_html_tag = false;
        StringBuilder current_word = new StringBuilder ();

        string[] lines = text.split ("\n");

        foreach (string line in lines) {
            // Skip YAML frontmatter
            if (line == "---" || line == "+++") {
                if (in_yaml) {
                    in_yaml = false;
                    continue;
                } else if (word_count == 0) {
                    in_yaml = true;
                    continue;
                }
            }

            if (in_yaml) {
                continue;
            }

            // Skip code blocks
            if (line.has_prefix ("```") || line.has_prefix ("~~~")) {
                in_code_block = !in_code_block;
                continue;
            }

            if (in_code_block) {
                continue;
            }

            // Process line character by character for word counting (respect UTF-8 boundaries)
            int index = 0;
            unichar c = 0;
            while (line.get_next_char (ref index, out c)) {

                // Skip HTML tags (simple detection)
                if (c == '<') {
                    in_html_tag = true;
                    continue;
                } else if (c == '>') {
                    in_html_tag = false;
                    continue;
                }

                if (in_html_tag) {
                    continue;
                }

                // Skip markdown formatting characters
                if (c == '*' || c == '#' || c == '_' || c == '`' || c == '>' ||
                    c == '|' || c == '=' || c == '+' || c == '[' || c == ']' ||
                    c == '(' || c == ')') {
                    continue;
                }

                // Word boundary detection
                if (c.isspace () || c.ispunct ()) {
                    if (current_word.len > 0) {
                        word_count++;
                        current_word.erase ();
                    }
                } else if (c.isalnum ()) {
                    current_word.append_unichar (c);
                }
            }

            // Handle word at end of line
            if (current_word.len > 0) {
                word_count++;
                current_word.erase ();
            }
        }

        return word_count;
    }

    public int get_word_count (string file_path) {
        DataInputStream? input = null;
        try {
            var file = File.new_for_path (file_path);
            if (!file.query_exists ()) {
                return 0;
            }

            input = new DataInputStream (file.read ());
            int word_count = 0;
            string? line;
            bool in_yaml = false;
            bool in_code_block = false;
            bool in_html_tag = false;
            StringBuilder current_word = new StringBuilder ();

            while ((line = input.read_line (null)) != null) {
                // Skip YAML frontmatter
                if (line == "---" || line == "+++") {
                    if (in_yaml) {
                        in_yaml = false;
                        continue;
                    } else if (word_count == 0) {
                        in_yaml = true;
                        continue;
                    }
                }

                if (in_yaml) {
                    continue;
                }

                // Skip code blocks
                if (line.has_prefix ("```") || line.has_prefix ("~~~")) {
                    in_code_block = !in_code_block;
                    continue;
                }

                if (in_code_block) {
                    continue;
                }

                // Process line character by character for word counting (respect UTF-8 boundaries)
                int index = 0;
                unichar c = 0;
                while (line.get_next_char (ref index, out c)) {

                    // Skip HTML tags (simple detection)
                    if (c == '<') {
                        in_html_tag = true;
                        continue;
                    } else if (c == '>') {
                        in_html_tag = false;
                        continue;
                    }

                    if (in_html_tag) {
                        continue;
                    }

                    // Skip markdown formatting characters
                    if (c == '*' || c == '#' || c == '_' || c == '`' || c == '>' ||
                        c == '|' || c == '=' || c == '+' || c == '[' || c == ']' ||
                        c == '(' || c == ')') {
                        continue;
                    }

                    // Word boundary detection
                    if (c.isspace () || c.ispunct ()) {
                        if (current_word.len > 0) {
                            word_count++;
                            current_word.erase ();
                        }
                    } else if (c.isalnum ()) {
                        current_word.append_unichar (c);
                    }
                }

                // Handle word at end of line
                if (current_word.len > 0) {
                    word_count++;
                    current_word.erase ();
                }
            }

            return word_count;
        } catch (Error e) {
            warning ("Could not get word count for %s: %s", file_path, e.message);
        } finally {
            if (input != null) {
                try {
                    input.close ();
                } catch (Error e) {
                    warning ("Could not close word count stream: %s", e.message);
                }
            }
        }

        return 0;
    }
}
