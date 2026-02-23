/*
 * Copyright (C) 2018-2024 M.W. Freed
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using ThiefMD.Widgets;

namespace ThiefMD.Controllers.FileImporter {

    private const string FILE_IMPORTER_ERROR_DOMAIN = "THIEFMD_FILE_IMPORTER_ERROR";

    private errordomain FileImporterError {
        INVALID_ARCHIVE
    }

    private string maybe_url_decode (string path) {
        string? decoded = Uri.unescape_string (path);
        if (decoded != null && decoded != "") {
            return decoded;
        }

        return path;
    }

    private bool list_contains (string needle, Gee.LinkedList<string> haystack, out string match) {
        foreach (string hay in haystack) {
            if (hay == needle) {
                match = hay;
                return true;
            }

            string decoded_hay = maybe_url_decode (hay);
            if (decoded_hay == needle) {
                match = decoded_hay;
                return true;
            }

            string decoded_needle = maybe_url_decode (needle);
            if (decoded_needle == hay) {
                match = hay;
                return true;
            }

            if (decoded_needle == decoded_hay) {
                match = decoded_hay;
                return true;
            }

            string stripped_hay = hay.replace ("../", "").replace ("./", "");
            if (stripped_hay == needle || needle.has_suffix (stripped_hay)) {
                match = stripped_hay;
                return true;
            }

            string stripped_decoded_hay = decoded_hay.replace ("../", "").replace ("./", "");
            if (stripped_decoded_hay == needle || needle.has_suffix (stripped_decoded_hay)) {
                match = stripped_decoded_hay;
                return true;
            }

            string stripped_decoded_needle = decoded_needle.replace ("../", "").replace ("./", "");
            if (stripped_hay == decoded_needle || stripped_decoded_hay == decoded_needle ||
                stripped_hay == stripped_decoded_needle || stripped_decoded_hay == stripped_decoded_needle ||
                stripped_decoded_needle.has_suffix (stripped_hay) ||
                stripped_decoded_needle.has_suffix (stripped_decoded_hay)) {
                match = stripped_decoded_hay;
                return true;
            }
        }

        match = "";
        return false;
    }

    private void throw_on_failure (Archive.Result result) throws FileImporterError {
        if (result != Archive.Result.OK) {
            throw new FileImporterError.INVALID_ARCHIVE ("Invalid archive file");
        }
    }

    private uint8[] read_archive_entry_bytes (Archive.Read archive) {
        ByteArray byte_buffer = new ByteArray ();

        while (true) {
            uint8[] chunk = new uint8[16384];
            ssize_t bytes_read = archive.read_data (chunk);
            if (bytes_read <= 0) {
                break;
            }

            byte_buffer.append (chunk[0:(int) bytes_read]);
        }

        return byte_buffer.data;
    }

    private string normalize_archive_relative_path (string path) {
        if (path == null) {
            return "";
        }

        string cleaned = path.strip ();
        cleaned = cleaned.replace ("\\", "/");

        while (cleaned.has_prefix ("./")) {
            cleaned = cleaned.substring (2);
        }

        if (cleaned.has_prefix ("/")) {
            cleaned = cleaned.substring (1);
        }

        while (cleaned.contains ("//")) {
            cleaned = cleaned.replace ("//", "/");
        }

        return cleaned;
    }

    private bool is_safe_archive_relative_path (string path) {
        string cleaned = normalize_archive_relative_path (path);
        if (cleaned == "") {
            return false;
        }

        if (cleaned.has_prefix ("/")) {
            return false;
        }

        if (cleaned.index_of (":") >= 0) {
            return false;
        }

        if (cleaned.has_prefix ("~") || cleaned.has_prefix ("$")) {
            return false;
        }

        if (cleaned.contains ("://")) {
            return false;
        }

        if (cleaned.has_suffix ("/")) {
            return false;
        }

        string[] segments = cleaned.split ("/");
        foreach (string segment in segments) {
            if (segment == "" || segment == "." || segment == "..") {
                return false;
            }
        }

        return true;
    }

    private string textpack_type_from_info_json (string info_json) {
        if (info_json == null || info_json == "") {
            return "";
        }

        try {
            Regex type_match = new Regex ("\"type\"\\s*:\\s*\"([^\"]+)\"");
            MatchInfo info;
            if (type_match.match (info_json, 0, out info)) {
                return info.fetch (1);
            }
        } catch (Error e) {
            warning ("Could not parse textpack info.json: %s", e.message);
        }

        return "";
    }

    private bool textpack_type_indicates_fountain (string type_name) {
        if (type_name == null || type_name == "") {
            return false;
        }

        string lowered = type_name.down ();
        if (lowered == "fountain") {
            return true;
        }

        int last_dot = lowered.last_index_of (".");
        if (last_dot >= 0 && (last_dot + 1) < lowered.length) {
            return lowered.substring (last_dot + 1) == "fountain";
        }

        return false;
    }

    private string textpack_import_extension (string text_entry_path, string archive_path, string textbundle_type = "") {
        string lowered_entry = text_entry_path.down ();
        if (lowered_entry.has_suffix (".fountain") || lowered_entry.has_suffix (".fou")) {
            return ".fountain";
        }

        if (textpack_type_indicates_fountain (textbundle_type)) {
            return ".fountain";
        }

        string lowered_archive = archive_path.down ();
        if (lowered_archive.has_suffix (".highland")) {
            return ".fountain";
        }

        return ".md";
    }

    public void import_file (string file_path, Sheets parent) {
        File import_f = File.new_for_path (file_path);
        string ext = file_path.substring (file_path.last_index_of (".") + 1).down ();
        string match_ext = ext;
        warning ("Importing (%s): %s", ext, import_f.get_path ());

        if (ext == "textpack" || ext == "highland") {
            import_textpack (file_path, parent);
            return;
        }

        if (ext == "bear2bk") {
            import_bear2bk (file_path, parent);
            return;
        }

        if (ext == "fdx") {
            import_fdx (file_path, parent);
            return;
        }

        if (match_ext.length >= 3) {
            match_ext = "*." + match_ext + ";";
        }

        if (ThiefProperties.SUPPORTED_IMPORT_FILES.index_of (match_ext) >= 0) {
            Gee.List<string> import_sayings = new Gee.LinkedList<string> ();
            import_sayings.add (_("Stealing file contents..."));
            import_sayings.add (_("This isn't plagiarism, it's a remix!"));
            import_sayings.add (_("NYT Best Seller, here we come!"));

            Thinking worker = new Thinking (_("Importing File"), () => {
                string dest_name = import_f.get_basename ();
                dest_name = dest_name.substring (0, dest_name.last_index_of ("."));
                if (is_fountain (import_f.get_basename ())) {
                    dest_name += ".fountain";
                } else {
                    dest_name += ".md";
                }
                debug ("Attempt to create: %s", dest_name);
                string dest_path = Path.build_filename (parent.get_sheets_path (), dest_name);
                if (can_open_file (import_f.get_basename ())) {
                    File copy_to = File.new_for_path (dest_path);
                    try {
                        import_f.copy (copy_to, FileCopyFlags.NONE);
                    } catch (Error e) {
                        warning ("Could not add file to library: %s", e.message);
                    }
                } else if (Pandoc.make_md_from_file (dest_path, import_f.get_path ())) {
                    if (ext == "docx" || ext == "odt" || ext == "epub" || ext == "fb2") {
                        string new_markdown = FileManager.get_file_contents (dest_path);
                        Gee.LinkedList<string> files_to_find = Pandoc.file_import_paths (new_markdown);
                        string formatted_markdown = FileManager.strip_external_formatters (new_markdown);
                        extract_files_to_dest (import_f.get_path (), files_to_find, parent.get_sheets_path ());
                        if (formatted_markdown != "") {
                            File write_twice = File.new_for_path (dest_path);
                            try {
                                FileManager.save_file (write_twice, formatted_markdown.data);
                            } catch (Error e) {
                                warning ("Could not strip external formatting: %s", e.message);
                            }
                        }
                    }
                }
            },
            import_sayings,
            ThiefApp.get_instance ());
            worker.run ();
        }

        parent.refresh ();
        ThiefApp.get_instance ().library.refresh_dir (parent);
    }

    public void extract_files_to_dest (string archive_path, Gee.LinkedList<string> files, string destination_path) {
        File arch_file = File.new_for_path (archive_path);
        File dest = File.new_for_path (destination_path);
        if (!arch_file.query_exists ()) {
            return;
        }

        try {
            debug ("Looking for requested files in archive");
            var archive = new Archive.Read ();
            throw_on_failure (archive.support_filter_all ());
            throw_on_failure (archive.support_format_all ());
            throw_on_failure (archive.open_filename (arch_file.get_path (), 10240));

            unowned Archive.Entry entry;
            while (archive.next_header (out entry) == Archive.Result.OK) {
                debug ("Found: %s", entry.pathname ());
                string extraction_path = "";
                if (list_contains (entry.pathname (), files, out extraction_path)) {
                    if (!is_safe_archive_relative_path (extraction_path)) {
                        debug ("Skipping unsafe extraction path: %s", extraction_path);
                        archive.read_data_skip ();
                        continue;
                    }

                    uint8[] bin_buffer = read_archive_entry_bytes (archive);

                    if (bin_buffer.length != 0) {
                        File dest_file = File.new_for_path (Path.build_filename (dest.get_path (), extraction_path));
                        File dest_parent = dest_file.get_parent ();
                        debug ("Extracting: %s to %s", entry.pathname (), dest_file.get_path ());
                        if (dest_parent != null) {
                            if (!dest_parent.query_exists ()) {
                                dest_parent.make_directory_with_parents ();
                            }
                            FileManager.save_file (dest_file, bin_buffer);
                        }
                    }
                } else {
                    archive.read_data_skip ();
                }
            }
        } catch (Error e) {
            warning ("Error loading archive: %s", e.message);
        }
    }

    public void import_textpack (string textpack_path, Sheets parent) {
        File textpack_file = File.new_for_path (textpack_path);
        if (!textpack_file.query_exists ()) {
            return;
        }

        Gee.List<string> import_sayings = new Gee.LinkedList<string> ();
        import_sayings.add (_("Unpacking your stories..."));
        import_sayings.add (_("Liberating your words!"));
        import_sayings.add (_("TextPack, meet ThiefMD!"));

        Thinking worker = new Thinking (_("Importing TextPack"), () => {
            string bundle_name = textpack_file.get_basename ();
            bundle_name = bundle_name.substring (0, bundle_name.last_index_of ("."));

            try {
                var archive = new Archive.Read ();
                throw_on_failure (archive.support_filter_all ());
                throw_on_failure (archive.support_format_all ());
                throw_on_failure (archive.open_filename (textpack_file.get_path (), 10240));

                uint8[]? text_data = null;
                string text_entry_path = "";
                string textbundle_type = "";

                unowned Archive.Entry entry;
                while (archive.next_header (out entry) == Archive.Result.OK) {
                    string entry_path = entry.pathname ();

                    if (entry_path.contains ("/")) {
                        string first_comp = entry_path.substring (0, entry_path.index_of ("/"));
                        string rest = entry_path.substring (entry_path.index_of ("/") + 1);
                        if (first_comp != "assets" && rest != "") {
                            entry_path = rest;
                        }
                    }

                    bool is_text = (entry_path == "text.md" ||
                        entry_path == "text.markdown" ||
                        entry_path == "text.fountain" ||
                        entry_path == "text.fou");

                    bool is_info = (entry_path == "info.json");

                    bool is_asset = entry_path.has_prefix ("assets/") &&
                        !entry_path.has_suffix ("/");

                    if (is_text || is_asset || is_info) {
                        uint8[] bin_buffer = read_archive_entry_bytes (archive);

                        if (bin_buffer.length != 0) {
                            if (is_text) {
                                text_entry_path = entry_path;
                                text_data = bin_buffer;
                            } else if (is_info) {
                                uint8[] info_data = bin_buffer;
                                if (info_data[info_data.length - 1] != 0) {
                                    info_data += 0;
                                }
                                textbundle_type = textpack_type_from_info_json ((string) info_data);
                            } else {
                                if (!is_safe_archive_relative_path (entry_path)) {
                                    debug ("Skipping unsafe textpack asset path: %s", entry_path);
                                    continue;
                                }
                                string safe_asset_path = normalize_archive_relative_path (entry_path);
                                string dest_path = Path.build_filename (parent.get_sheets_path (), safe_asset_path);
                                File dest_file = File.new_for_path (dest_path);
                                File dest_parent = dest_file.get_parent ();
                                try {
                                    if (dest_parent != null && !dest_parent.query_exists ()) {
                                        dest_parent.make_directory_with_parents ();
                                    }
                                    FileManager.save_file (dest_file, bin_buffer);
                                } catch (Error e) {
                                    warning ("Could not save extracted file: %s", e.message);
                                }
                            }
                        }
                    } else {
                        archive.read_data_skip ();
                    }
                }

                if (text_data != null && text_entry_path != "") {
                    string ext = textpack_import_extension (text_entry_path, textpack_path, textbundle_type);
                    string dest_path = Path.build_filename (parent.get_sheets_path (), bundle_name + ext);
                    File dest_file = File.new_for_path (dest_path);
                    File dest_parent = dest_file.get_parent ();
                    try {
                        if (dest_parent != null && !dest_parent.query_exists ()) {
                            dest_parent.make_directory_with_parents ();
                        }
                        FileManager.save_file (dest_file, text_data);
                    } catch (Error e) {
                        warning ("Could not save extracted file: %s", e.message);
                    }
                }

            } catch (Error e) {
                warning ("Could not import textpack: %s", e.message);
            }
        }, import_sayings, ThiefApp.get_instance ());

        worker.run ();
        parent.refresh ();
        ThiefApp.get_instance ().library.refresh_dir (parent);
    }

    public void import_bear2bk (string archive_path, Sheets parent) {
        File arch_file = File.new_for_path (archive_path);
        if (!arch_file.query_exists ()) {
            return;
        }

        Gee.List<string> import_sayings = new Gee.LinkedList<string> ();
        import_sayings.add (_("Stealing from bears..."));
        import_sayings.add (_("Liberating your notes!"));
        import_sayings.add (_("Bear2bk, meet ThiefMD!"));

        Thinking worker = new Thinking (_("Importing Bear Notes"), () => {
            extract_bear2bk (archive_path, parent.get_sheets_path ());
        }, import_sayings, ThiefApp.get_instance ());

        worker.run ();
        parent.refresh ();
        ThiefApp.get_instance ().library.refresh_dir (parent);
    }

    public void extract_bear2bk (string archive_path, string destination_path) {
        File arch_file = File.new_for_path (archive_path);
        if (!arch_file.query_exists ()) {
            return;
        }

        try {
            var archive = new Archive.Read ();
            throw_on_failure (archive.support_filter_all ());
            throw_on_failure (archive.support_format_all ());
            throw_on_failure (archive.open_filename (arch_file.get_path (), 10240));

            unowned Archive.Entry entry;
            while (archive.next_header (out entry) == Archive.Result.OK) {
                string pathname = entry.pathname ();

                if (pathname.contains (".textbundle/text.md") ||
                    pathname.contains (".textbundle/text.markdown")) {
                    int bundle_end = pathname.index_of (".textbundle/");
                    string bundle_path = pathname.substring (0, bundle_end);
                    int last_sep = bundle_path.last_index_of ("/");
                    string note_name = (last_sep >= 0) ? bundle_path.substring (last_sep + 1) : bundle_path;
                    if (note_name == "" || note_name.contains ("..") || note_name.contains ("/") || note_name.contains ("\\")) {
                        archive.read_data_skip ();
                        continue;
                    }
                    string dest_file_name = note_name + ".md";

                    uint8[] text_buffer = read_archive_entry_bytes (archive);

                    if (text_buffer.length != 0) {
                        File dest_file = File.new_for_path (Path.build_filename (destination_path, dest_file_name));
                        try {
                            FileManager.save_file (dest_file, text_buffer);
                        } catch (Error e) {
                            warning ("Could not save note from bear2bk: %s", e.message);
                        }
                    }
                } else if (pathname.contains (".textbundle/assets/")) {
                    int assets_start = pathname.index_of (".textbundle/assets/") + ".textbundle/assets/".length;
                    string asset_name = pathname.substring (assets_start);
                    if (!is_safe_archive_relative_path (asset_name)) {
                        archive.read_data_skip ();
                        continue;
                    }

                    uint8[] asset_buffer = read_archive_entry_bytes (archive);

                    if (asset_buffer.length != 0) {
                        string safe_asset_name = normalize_archive_relative_path (asset_name);
                        File dest_file = File.new_for_path (Path.build_filename (destination_path, "assets", safe_asset_name));
                        File dest_parent_dir = dest_file.get_parent ();
                        try {
                            if (dest_parent_dir != null && !dest_parent_dir.query_exists ()) {
                                dest_parent_dir.make_directory_with_parents ();
                            }
                            FileManager.save_file (dest_file, asset_buffer);
                        } catch (Error e) {
                            warning ("Could not save asset from bear2bk: %s", e.message);
                        }
                    }
                } else {
                    archive.read_data_skip ();
                }
            }
        } catch (Error e) {
            warning ("Error importing bear2bk: %s", e.message);
        }
    }

    public void import_fdx (string fdx_path, Sheets parent) {
        File fdx_file = File.new_for_path (fdx_path);
        if (!fdx_file.query_exists ()) {
            return;
        }

        Gee.List<string> import_sayings = new Gee.LinkedList<string> ();
        import_sayings.add (_("Raiding the screenplay vault..."));
        import_sayings.add (_("Converting Final Draft to Fountain!"));
        import_sayings.add (_("Lights, camera, import!"));

        Thinking worker = new Thinking (_("Importing FDX"), () => {
            string bundle_name = fdx_file.get_basename ();
            bundle_name = bundle_name.substring (0, bundle_name.last_index_of ("."));
            string dest_path = Path.build_filename (parent.get_sheets_path (), bundle_name + ".fountain");

            string fdx_content = FileManager.get_file_contents (fdx_file.get_path ());
            string fountain_content = FountainFdx.fdx_to_fountain (fdx_content);

            if (fountain_content != "") {
                File dest_file = File.new_for_path (dest_path);
                try {
                    FileManager.save_file (dest_file, fountain_content.data);
                } catch (Error e) {
                    warning ("Could not save converted FDX file: %s", e.message);
                }
            }
        }, import_sayings, ThiefApp.get_instance ());

        worker.run ();
        parent.refresh ();
        ThiefApp.get_instance ().library.refresh_dir (parent);
    }
}
