/*
 * Copyright (C) 2018-2024 M.W. Freed
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using ThiefMD;

namespace ThiefMD.Controllers.FileExporter {
    // AE_IFREG from libarchive: regular file mode for archive entries
    private const uint ARCHIVE_IFREG = 0100000;
    // Shared info.json content for TextBundle-compliant archives
    private const string TEXTBUNDLE_INFO_JSON = """{"version":2,"type":"net.daringfireball.markdown","transient":false,"creatorURL":"https://thiefmd.com","creatorIdentifier":"com.github.kmwallio.thiefmd"}""";
    // info.json for fountain screenplay textpacks
    private const string TEXTBUNDLE_FOUNTAIN_INFO_JSON = """{"version":2,"type":"com.quoteunquoteapps.fountain","transient":false,"creatorURL":"https://thiefmd.com","creatorIdentifier":"com.github.kmwallio.thiefmd"}""";

    public bool export_textpack (string folder_path, string textpack_path) {
        try {
            var md_files = new Gee.LinkedList<string> ();
            collect_exportable_files (folder_path, md_files);

            var combined = new StringBuilder ();
            foreach (string file_path in md_files) {
                string content = FileManager.get_file_contents (file_path);
                combined.append (content);
                combined.append ("\n\n");
            }
            string markdown_content = combined.str;

            Gee.Map<string, string> images = Pandoc.file_image_map (markdown_content, folder_path);

            string textbundle_markdown = markdown_content;
            foreach (var img_entry in images.entries) {
                string asset_name = "assets/" + Path.get_basename (img_entry.value);
                textbundle_markdown = textbundle_markdown.replace (img_entry.key, asset_name);
            }

            var writer = new Archive.Write ();
            if (writer.set_format_zip () != Archive.Result.OK) {
                warning ("Could not set zip format for textpack");
                return false;
            }
            if (writer.open_filename (textpack_path) != Archive.Result.OK) {
                warning ("Could not open textpack for writing: %s", textpack_path);
                return false;
            }

            textpack_add_string (writer, "info.json", TEXTBUNDLE_INFO_JSON);
            textpack_add_string (writer, "text.md", textbundle_markdown);

            foreach (var img_entry in images.entries) {
                string abs_path = img_entry.value;
                string asset_name = "assets/" + Path.get_basename (abs_path);
                textpack_add_file (writer, asset_name, abs_path);
            }

            writer.close ();
            return true;
        } catch (Error e) {
            warning ("Could not create textpack: %s", e.message);
            return false;
        }
    }

    public bool export_textpack_from_markdown (string markdown_content, string textpack_path, string base_path = "", bool is_fountain = false) {
        try {
            Gee.Map<string, string> images = Pandoc.file_image_map (markdown_content, base_path);

            string bundle_markdown = markdown_content;
            foreach (var img_entry in images.entries) {
                string asset_name = "assets/" + Path.get_basename (img_entry.value);
                bundle_markdown = bundle_markdown.replace (img_entry.key, asset_name);
            }

            var writer = new Archive.Write ();
            if (writer.set_format_zip () != Archive.Result.OK) {
                warning ("Could not set zip format for textpack");
                return false;
            }
            if (writer.open_filename (textpack_path) != Archive.Result.OK) {
                warning ("Could not open textpack for writing: %s", textpack_path);
                return false;
            }

            if (is_fountain) {
                textpack_add_string (writer, "info.json", TEXTBUNDLE_FOUNTAIN_INFO_JSON);
                textpack_add_string (writer, "text.fountain", bundle_markdown);
            } else {
                textpack_add_string (writer, "info.json", TEXTBUNDLE_INFO_JSON);
                textpack_add_string (writer, "text.md", bundle_markdown);
            }

            foreach (var img_entry in images.entries) {
                string asset_name = "assets/" + Path.get_basename (img_entry.value);
                textpack_add_file (writer, asset_name, img_entry.value);
            }

            writer.close ();
            return true;
        } catch (Error e) {
            warning ("Could not create textpack from markdown: %s", e.message);
            return false;
        }
    }

    private void collect_exportable_files (string folder_path, Gee.LinkedList<string> files) {
        try {
            Dir dir = Dir.open (folder_path, 0);
            string? name = null;
            var file_list = new Gee.LinkedList<string> ();
            var dir_list = new Gee.LinkedList<string> ();

            while ((name = dir.read_name ()) != null) {
                if (name.has_prefix (".")) {
                    continue;
                }
                string full_path = Path.build_filename (folder_path, name);
                if (FileUtils.test (full_path, FileTest.IS_DIR)) {
                    dir_list.add (full_path);
                } else if (exportable_file (name)) {
                    file_list.add (full_path);
                }
            }

            file_list.sort ((a, b) => a.collate (b));
            foreach (string file_path in file_list) {
                files.add (file_path);
            }

            dir_list.sort ((a, b) => a.collate (b));
            foreach (string directory in dir_list) {
                collect_exportable_files (directory, files);
            }
        } catch (Error e) {
            warning ("Could not scan folder for export: %s", e.message);
        }
    }

    private void textpack_add_string (Archive.Write writer, string name, string data) {
        var entry = new Archive.Entry ();
        entry.set_pathname (name);
        entry.set_size (data.length);
        entry.set_filetype (ARCHIVE_IFREG);
        entry.set_perm (0644);
        writer.write_header (entry);
        writer.write_data (data.data[0:data.length]);
    }

    private void textpack_add_file (Archive.Write writer, string archive_name, string file_path) {
        try {
            File asset_file = File.new_for_path (file_path);
            if (!asset_file.query_exists ()) {
                return;
            }

            uint8[] data;
            asset_file.load_contents (null, out data, null);

            var entry = new Archive.Entry ();
            entry.set_pathname (archive_name);
            entry.set_size (data.length);
            entry.set_filetype (ARCHIVE_IFREG);
            entry.set_perm (0644);
            writer.write_header (entry);
            writer.write_data (data);
        } catch (Error e) {
            warning ("Could not add asset to textpack: %s", e.message);
        }
    }
}
