/*
 * Copyright (C) 2018-2024 M.W. Freed
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using ThiefMD;

namespace ThiefMD.Controllers.FileMetadata {

    // Static regex to avoid recompilation on every call
    private static Regex? yaml_headers_regex = null;

    public Gee.Map<string, string> get_yaml_kvp (string markdown) {
        Gee.Map<string, string> kvps = new Gee.HashMap<string, string> ();
        string buffer = markdown;

        Regex headers = null;
        try {
            headers = new Regex ("^\\s*(.+?)\\s*[=:]\\s+(.*)", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
        } catch (Error e) {
            warning ("Could not compile regex: %s", e.message);
        }

        if (buffer.has_prefix ("---" + ThiefProperties.THIEF_MARK_CONST) || buffer.has_prefix ("+++" + ThiefProperties.THIEF_MARK_CONST)) {
            buffer = buffer.replace (ThiefProperties.THIEF_MARK_CONST, "");
        }

        string buffer_prefix = (buffer.length > 4) ? buffer[0:4] : "";
        if (buffer.length > 4 && (buffer_prefix == "---\n" || buffer_prefix == "+++\n")) {
            int i = 0;
            int last_newline = 3;
            int next_newline;
            bool valid_frontmatter = true;
            string line = "";

            while (valid_frontmatter) {
                next_newline = buffer.index_of_char ('\n', last_newline + 1);
                if (next_newline == -1 && !((buffer.length > last_newline + 1) && (buffer.substring (last_newline + 1).has_prefix ("---") || buffer.substring (last_newline + 1).has_prefix ("+++")))) {
                    valid_frontmatter = false;
                    break;
                }

                if (next_newline == -1) {
                    line = buffer.substring (last_newline + 1);
                } else {
                    line = buffer[last_newline + 1:next_newline];
                }
                line = line.replace (ThiefProperties.THIEF_MARK_CONST, "");
                last_newline = next_newline;

                if (line == "---" || line == "+++") {
                    break;
                }

                if (headers != null) {
                    MatchInfo matches;
                    if (headers.match (line, RegexMatchFlags.NOTEMPTY_ATSTART, out matches)) {
                        string key = matches.fetch (1).chug ().chomp ();
                        string value = matches.fetch (2).chug ().chomp ();
                        if (value.has_prefix ("\"") && value.has_suffix ("\"")) {
                            value = value.substring (1, value.length - 2);
                        }

                        if (!kvps.has_key (key)) {
                            kvps.set (key, value);
                        } else {
                            if (key == matches.fetch (1)) {
                                kvps.set (key, value);
                            }
                        }
                    } else {
                        line = line.down ().chomp ();
                        if (!line.has_prefix ("-") && line != "") {
                            valid_frontmatter = false;
                            break;
                        }
                    }
                } else {
                    string quick_parse = line.chomp ();
                    int split = quick_parse.index_of (":") != -1 ? quick_parse.index_of (":") : quick_parse.index_of ("=");
                    if (split != -1) {
                        string match = quick_parse.substring (0, split);
                        string key = quick_parse.substring (0, split).chug ().chomp ();
                        string value = quick_parse.substring (split + 1).chug ().chomp ();
                        if (value.has_prefix ("\"") && value.has_suffix ("\"")) {
                            value = value.substring (1, value.length - 2);
                        }
                        if (!kvps.has_key (key)) {
                            kvps.set (key, value);
                        } else {
                            if (key == match) {
                                kvps.set (key, value);
                            }
                        }
                    }
                }

                i++;
            }

            if (!valid_frontmatter) {
                kvps = new Gee.HashMap<string, string> ();
            }
        }

        return kvps;
    }

    public string get_yamlless_markdown (
        string markdown,
        int lines,
        out string title,
        out string date,
        bool non_empty = true,
        bool include_title = true,
        bool include_date = true)
    {
        string buffer = markdown;
        Regex headers = null;
        try {
            headers = new Regex ("^\\s*(.+?)\\s*[=:]\\s+(.*)", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
        } catch (Error e) {
            warning ("Could not compile regex: %s", e.message);
        }

        string temp_title = "";
        string temp_date = "";

        MatchInfo matches;
        var markout = new StringBuilder ();
        int mklines = 0;

        if (buffer.has_prefix ("---" + ThiefProperties.THIEF_MARK_CONST) || buffer.has_prefix ("+++" + ThiefProperties.THIEF_MARK_CONST)) {
            buffer = buffer.replace (ThiefProperties.THIEF_MARK_CONST, "");
        }

        string buffer_prefix = (buffer.length > 4) ? buffer[0:4] : "";
        if (buffer.length > 4 && ((buffer_prefix == "---\n") || (buffer_prefix == "+++\n"))) {
            int i = 0;
            int last_newline = 3;
            int next_newline;
            bool valid_frontmatter = true;
            string line = "";

            while (valid_frontmatter) {
                next_newline = buffer.index_of_char ('\n', last_newline + 1);
                if (next_newline == -1 && !((buffer.length > last_newline + 1) && (buffer.substring (last_newline + 1).has_prefix ("---") || buffer.substring (last_newline + 1).has_prefix ("+++")))) {
                    valid_frontmatter = false;
                    break;
                }

                if (next_newline == -1) {
                    line = buffer.substring (last_newline + 1);
                } else {
                    line = buffer[last_newline + 1:next_newline];
                }
                line = line.replace (ThiefProperties.THIEF_MARK_CONST, "");
                last_newline = next_newline;

                if (line == "---" || line == "+++") {
                    break;
                }

                if (headers != null) {
                    if (headers.match (line, RegexMatchFlags.NOTEMPTY_ATSTART, out matches)) {
                        if (matches.fetch (1).ascii_down () == "title") {
                            temp_title = matches.fetch (2).chug ().chomp ();
                            if (temp_title.has_prefix ("\"") && temp_title.has_suffix ("\"")) {
                                temp_title = temp_title.substring (1, temp_title.length - 2);
                            }
                            if (include_title) {
                                markout.append ("# " + temp_title + "\n");
                                mklines++;
                            }
                        } else if (matches.fetch (1).ascii_down () == "date") {
                            temp_date = matches.fetch (2).chug ().chomp ();
                            if (include_date) {
                                markout.append ("## " + temp_date + "\n");
                                mklines++;
                            }
                        }
                    } else {
                        line = line.down ().chomp ();
                        if (!line.has_prefix ("-") && line != "") {
                            valid_frontmatter = false;
                            break;
                        }
                    }
                } else {
                    string quick_parse = line.chomp ();
                    if (quick_parse.has_prefix ("title")) {
                        temp_title = quick_parse.substring (quick_parse.index_of (":") + 1);
                        if (temp_title.has_prefix ("\"") && temp_title.has_suffix ("\"")) {
                            temp_title = temp_title.substring (1, temp_title.length - 2);
                        }
                        if (include_title) {
                            markout.append ("# " + temp_title);
                            mklines++;
                        }
                    } else if (quick_parse.has_prefix ("date")) {
                        temp_date = quick_parse.substring (quick_parse.index_of (":") + 1).chug ().chomp ();
                        if (include_date) {
                            markout.append ("## " + temp_date);
                            mklines++;
                        }
                    }
                }

                i++;
            }

            if (!valid_frontmatter) {
                markout.erase ();
                markout.append (markdown);
            } else {
                markout.append (buffer[last_newline:buffer.length]);
            }
        } else {
            markout.append (markdown);
        }

        title = temp_title;
        date = temp_date;

        return markout.str;
    }

    public string get_file_lines_yaml (
        string file_path,
        int lines,
        bool non_empty_lines_only,
        out string title,
        out string date)
    {
        var markdown = new StringBuilder ();
        string temp_title = "";
        string temp_date = "";
        DataInputStream? input = null;

        try {
            if (yaml_headers_regex == null) {
                yaml_headers_regex = new Regex ("^\\s*(.+?)\\s*[=:]\\s+(.+)", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
            }

            var file = File.new_for_path (file_path);
            if (!file.query_exists ()) {
                warning ("File does not exist: %s", file_path);
                title = temp_title;
                date = temp_date;
                return "";
            }

            debug ("Reading %s", file.get_path ());
            input = new DataInputStream (file.read ());
            int lines_read = 0;
            string? line;
            bool in_yaml = false;
            bool first_line = true;

            while ((line = input.read_line (null)) != null) {
                if (lines > 0 && lines_read >= lines) {
                    break;
                }

                string trimmed = line.chomp ();

                if (non_empty_lines_only && trimmed == "") {
                    continue;
                }

                if (trimmed == "---" || trimmed == "+++") {
                    if (in_yaml) {
                        in_yaml = false;
                        continue;
                    } else if (lines_read == 0) {
                        in_yaml = true;
                        continue;
                    }
                }

                if (!in_yaml) {
                    if (temp_title == "" && line.has_prefix ("#")) {
                        int space_idx = line.index_of (" ");
                        if (space_idx != -1) {
                            temp_title = line.substring (space_idx).chug ().chomp ();
                        }
                    }

                    if (!first_line) {
                        markdown.append_c ('\n');
                    }
                    markdown.append (trimmed);
                    lines_read++;
                    first_line = false;
                } else {
                    MatchInfo matches;
                    if (yaml_headers_regex.match (trimmed, RegexMatchFlags.NOTEMPTY, out matches)) {
                        string key = matches.fetch (1).chug ().chomp ().ascii_down ();
                        string value = matches.fetch (2).chug ().chomp ();

                        if (value.has_prefix ("\"") && value.has_suffix ("\"") && value.length >= 2) {
                            value = value.substring (1, value.length - 2);
                        }

                        if (key == "title") {
                            temp_title = value;
                            if (!first_line) {
                                markdown.append_c ('\n');
                            }
                            markdown.append ("# ").append (temp_title);
                            lines_read++;
                            first_line = false;
                        } else if (key.has_prefix ("date")) {
                            temp_date = value;
                            if (!first_line) {
                                markdown.append_c ('\n');
                            }
                            markdown.append (temp_date);
                            lines_read++;
                            first_line = false;
                        }
                    }
                }
            }

            if (lines_read == 1) {
                markdown.append_c ('\n');
            }

        } catch (Error e) {
            warning ("Error reading %s: %s", file_path, e.message);
        } finally {
            if (input != null) {
                try {
                    input.close ();
                } catch (Error e) {
                    warning ("Could not close file lines stream: %s", e.message);
                }
            }
        }

        title = temp_title;
        date = temp_date;

        return markdown.str;
    }
}
