/*
 * Copyright (C) 2017 Lains
 * 
 * Modified July 5, 2018
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

using ThiefMD;
using ThiefMD.Widgets;

namespace ThiefMD.Controllers.FileManager {
    public static bool disable_save = false;

    public void import_file (string file_path, Sheets parent) {
        FileImporter.import_file (file_path, parent);
    }

    private string strip_external_formatters (string markdown) {
        string resdown = markdown;
        try {
            Regex non_supported_tags = new Regex ("(\\[\\]\\{[=\\#sw\\.[^\\}]*\\n?\\r?[^\\}]*?\\})", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
            Regex non_supported_tags2 = new Regex ("(\\{[=\\#sw\\.[^\\}]*\\n?\\r?[^\\}]*?\\})", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
            Regex random_colons = new Regex ("^([:\\\\])+\\s*$", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
            Regex empty_lines = new Regex ("\\n\\s*\\n\\s*\\n", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
            Regex end_break = new Regex ("\\\\$", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
            Regex sentence_break = new Regex ("([a-zA-Z,;:\\\"])\\n([a-zA-Z,;:\\\"\\()])", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);

            resdown = non_supported_tags.replace (resdown, resdown.length, 0, "");
            resdown = non_supported_tags2.replace (resdown, resdown.length, 0, "");
            resdown = random_colons.replace (resdown, resdown.length, 0, "");
            resdown = empty_lines.replace (resdown, resdown.length, 0, "\n\n");
            resdown = end_break.replace (resdown, resdown.length, 0, "  ");
            resdown = sentence_break.replace (resdown, resdown.length, 0, "\\1 \\2");
            resdown = resdown.replace ("\n\n\n", "\n\n"); // Switch 3 empty lines to 2
            resdown = resdown.replace ("\n\n\n", "\n\n"); // Switch 3 empty lines to 2
            resdown = resdown.replace ("\\\'", "'");
            resdown = resdown.replace ("\\\"", "\"");
        } catch (Error e) {
            warning ("Could not strip special formatters: %s", e.message);
        }
        return resdown;
    }

    internal string maybe_url_decode (string value) {
        string? decoded = Uri.unescape_string (value, null);
        if (decoded != null && decoded != "") {
            return decoded;
        }

        return value;
    }

    internal string textpack_import_extension (string entry_path, string archive_path, string textbundle_type = "") {
        string lowered_entry = entry_path.down ();
        string lowered_archive = archive_path.down ();
        string lowered_type = textbundle_type.down ();
        string type_suffix = lowered_type;
        int type_dot = lowered_type.last_index_of (".");
        if (type_dot >= 0 && type_dot < lowered_type.length - 1) {
            type_suffix = lowered_type.substring (type_dot + 1);
        }

        if (lowered_entry == "text.fountain" || lowered_entry == "text.fou") {
            return ".fountain";
        }

        if ((type_suffix == "fountain" || lowered_type == "io.fountain.screenplay") &&
            (lowered_entry == "text.md" || lowered_entry == "text.markdown")) {
            return ".fountain";
        }

        if (lowered_archive.has_suffix (".highland") &&
            (lowered_entry == "text.md" || lowered_entry == "text.markdown")) {
            return ".fountain";
        }

        if (lowered_entry == "text.markdown") {
            return ".md";
        }

        int dot_index = entry_path.last_index_of (".");
        if (dot_index >= 0) {
            return entry_path.substring (dot_index);
        }

        return ".md";
    }

    public void extract_files_to_dest (string archive_path, Gee.LinkedList<string> files, string destination_path) {
        FileImporter.extract_files_to_dest (archive_path, files, destination_path);
    }

    public void load_css_pkg (File css_pkg) {
        if (!css_pkg.query_exists ()) {
            return;
        }

        try {
            var archive = new Archive.Read ();
            throw_on_failure (archive.support_filter_all ());
            throw_on_failure (archive.support_format_all ());
            throw_on_failure (archive.open_filename (css_pkg.get_path (), 10240));
            string theme_name = css_pkg.get_basename ();
            theme_name = theme_name.substring (0, theme_name.last_index_of ("."));
            if (theme_name == null || theme_name.chug ().chomp () == "") {
                return;
            }
            File theme_dest = File.new_for_path (Path.build_filename (UserData.css_path, theme_name));

            // Browse files in archive.
            unowned Archive.Entry entry;
            while (archive.next_header (out entry) == Archive.Result.OK) {
                // Extract theme into memory
                if (entry.pathname ().has_suffix (".css")){
                    uint8[] buffer = null;
                    Posix.off_t offset;
                    string css_buffer = "";
                    while (archive.read_data_block (out buffer, out offset) == Archive.Result.OK) {
                        if (buffer == null) {
                            break;
                        }
                        if (buffer[buffer.length - 1] != 0) {
                            buffer += 0;
                        }
                        css_buffer += (string)buffer;
                    }

                    if (!theme_dest.query_exists ()) {
                        theme_dest.make_directory_with_parents ();
                    }

                    string dest = "preview.css";
                    if (entry.pathname ().down ().has_suffix("print.css") || entry.pathname ().down ().has_suffix("pdf.css")) {
                        dest = "print.css";
                    }
                    File dest_file = File.new_for_path (Path.build_filename (theme_dest.get_path (), dest));
                    save_file (dest_file, css_buffer.data);
                } else {
                    archive.read_data_skip ();
                }
            }
        } catch (Error e) {
            warning ("Error loading archive: %s", e.message);
        }
    }

    private void throw_on_failure (Archive.Result res) throws Error {
        if ((res == Archive.Result.OK) ||
            (res == Archive.Result.WARN)) {
            return;
        }

        throw new ThiefError.FILE_NOT_FOUND ("Could not read archive");
    }

    public void save_file (File save_file, uint8[] buffer) throws Error {
        if (save_file.query_exists ()) {
            save_file.delete ();
        }

        var output = new DataOutputStream (save_file.create(FileCreateFlags.REPLACE_DESTINATION));
        long written = 0;
        while (written < buffer.length)
            written += output.write (buffer[written:buffer.length]);
    }

    public string save_temp_file (string text, string ext = "md") {
        string res_file = "";
        string cache_path = Path.build_filename (Environment.get_user_cache_dir (), "com.github.kmwallio.thiefmd");
        var cache_folder = File.new_for_path (cache_path);
        if (!cache_folder.query_exists ()) {
            try {
                cache_folder.make_directory_with_parents ();
            } catch (Error e) {
                warning ("Error: %s\n", e.message);
            }
        }

        Rand probably_a_better_solution_than_this = new Rand ();
        string random_name = "%d.%s".printf (probably_a_better_solution_than_this.int_range (100000, 999999), ext);
        File tmp_file = cache_folder.get_child (random_name);

        try {
            save_file (tmp_file, text.data);
            res_file = tmp_file.get_path ();
        } catch (Error e) {
            warning ("Failed temp file generation: %s", e.message);
        }

        return res_file;
    }

    public void open_file (string file_path, out Widgets.Editor editor) {
        bool file_opened = false;
        var lock = new FileLock ();
        var settings = AppSettings.get_default ();

        var file = File.new_for_path (file_path);

        if (file.query_exists ()) {
            string filename = file.get_path ();
            debug ("Reading %s\n", filename);
            editor = new Widgets.Editor (filename);
            settings.last_file = filename;
            file_opened = true;
        } else {
            editor = null;
            debug ("File does not exist\n");
        }
    }

    public bool copy_item (string source_file, string destination_folder) throws Error
    {
        File to_move = File.new_for_path (source_file);
        File final_destination = File.new_for_path (Path.build_filename (destination_folder, to_move.get_basename ()));
        return to_move.copy (final_destination, FileCopyFlags.NONE);
    }

    public bool move_item (string source_file, string destination_folder) throws Error
    {
        bool moved = false;
        bool is_active = false;

        if (SheetManager.close_active_file (source_file))
        {
            is_active = true;
        }

        File to_move = File.new_for_path (source_file);
        File final_destination = File.new_for_path (Path.build_filename (destination_folder, to_move.get_basename ()));
        moved = to_move.move (final_destination, FileCopyFlags.NONE);

        return moved;
    }

    public bool move_to_trash (string file_path)
    {
        bool moved = false;
        File to_delete = File.new_for_path (file_path);
        if (!to_delete.query_exists ()) {
            return true;
        }

        try {
            moved = to_delete.trash ();
        } catch (Error e) {
            warning ("Error: %s", e.message);
        }

        return moved;
    }

    public static string get_file_contents (string file_path) {
        // var lock = new FileLock ();
        string file_contents = "";

        try {
            var file = File.new_for_path (file_path);

            if (file.query_exists ()) {
                string filename = file.get_path ();
                debug ("Reading %s\n", filename);
                GLib.FileUtils.get_contents (filename, out file_contents);
            }
        } catch (Error e) {
            warning ("Error: %s", e.message);
        }

        return file_contents;
    }

    public int get_word_count_from_string (string text) {
        return FileWordCount.get_word_count_from_string (text);
    }

    public int get_word_count (string file_path) {
        return FileWordCount.get_word_count (file_path);
    }

    public bool get_parsed_markdown (string raw_mk, out string processed_mk) {
        return Pandoc.generate_discount_html (raw_mk, out processed_mk);
    }

    public Gee.Map<string, string> get_yaml_kvp (string markdown) {
        return FileMetadata.get_yaml_kvp (markdown);
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
        return FileMetadata.get_yamlless_markdown (markdown, lines, out title, out date, non_empty, include_title, include_date);
    }
    
    public string get_file_lines_yaml (
        string file_path,
        int lines,
        bool non_empty_lines_only,
        out string title,
        out string date)
    {
        return FileMetadata.get_file_lines_yaml (file_path, lines, non_empty_lines_only, out title, out date);
    }

    public bool add_ignore_folder (string directory_path)
    {
        File ignore_dir = File.new_for_path (directory_path);
        File parent_dir = ignore_dir.get_parent ();
        bool file_created = false;
        string? buffer;
        if (parent_dir.query_exists ()) {
            var ignore_file = parent_dir.get_child (".thiefignore");
            if (!ignore_file.query_exists ()) {
                // Create new .thiefignore file
                buffer = ignore_dir.get_basename ();
                if (buffer == null) {
                    return false;
                }
            } else {
                buffer = get_file_lines (ignore_file.get_path (), 100, true) + "\n" + ignore_dir.get_basename ();
                try {
                    ignore_file.delete ();
                } catch (Error e) {
                    warning ("Error: %s\n", e.message);
                }
            }
            try {
                uint8[] binbuffer = buffer.data;
                save_file (ignore_file, binbuffer);
                file_created = true;
            } catch (Error e) {
                warning ("Exception found: "+ e.message);
            }
        }

        return file_created;
    }

    public string get_file_lines (string file_path, int lines, bool non_empty = true) {
        var lock = new FileLock ();
        string file_contents = "";
        DataInputStream? input = null;

        if (lines <= 0) {
            return get_file_contents(file_path);
        }

        try {
            var file = File.new_for_path (file_path);

            if (file.query_exists ()) {
                string filename = file.get_path ();
                debug ("Reading %s\n", filename);

                input = new DataInputStream (file.read ());
                int lines_read = 0;
                string line;

                while (((line = input.read_line (null)) != null) && (lines_read < lines)) {
                    if ((!non_empty) || (line.chomp() != "")) {
                        file_contents += ((lines_read == 0) ? "" :"\n") + line.chomp();
                        lines_read++;
                    }
                }

                if (lines_read == 1) {
                    file_contents += "\n";
                }

            } else {
                warning ("File does not exist\n");
            }
        } catch (Error e) {
            warning ("Error: %s", e.message);
        } finally {
            if (input != null) {
                try {
                    input.close ();
                } catch (Error e) {
                    warning ("Could not close file lines internal stream: %s", e.message);
                }
            }
        }

        return file_contents;
    }

    public void save () throws Error {
        debug ("Save button pressed.");

        SheetManager.save_active ();
    }

    public static bool create_sheet (string parent_folder, string file_name) {
        var lock = new FileLock ();
        File parent_dir = File.new_for_path (parent_folder);
        bool file_created = false;

        if (parent_dir.query_exists ()) {
            var new_file = parent_dir.get_child (file_name);
            // Make sure the file doesn't exist.
            if (!new_file.query_exists ()) {
                string buffer = "";
                uint8[] binbuffer = buffer.data;

                try {
                    save_file (new_file, binbuffer);
                    file_created = true;
                } catch (Error e) {
                    warning ("Exception found: "+ e.message);
                }
            }
        }

        return file_created;
    }

    // Import a TextPack (.textpack) archive into a library folder.
    // TextBundle spec: https://textbundle.org/spec/
    public void import_textpack (string textpack_path, Sheets parent) {
        FileImporter.import_textpack (textpack_path, parent);
    }

    // Imports notes from a Bear2bk backup file into a library folder.
    // A .bear2bk is a zip containing one .textbundle per note, each with a text.md inside.
    public void import_bear2bk (string archive_path, Sheets parent) {
        FileImporter.import_bear2bk (archive_path, parent);
    }

    // Extracts notes and assets from a bear2bk archive into a destination folder.
    // Each note's text.md lands as <note name>.md; assets are extracted under assets/.
    public void extract_bear2bk (string archive_path, string destination_path) {
        FileImporter.extract_bear2bk (archive_path, destination_path);
    }

    // Export a folder's markdown files as a TextPack (.textpack) archive.
    // TextBundle spec: https://textbundle.org/spec/
    public bool export_textpack (string folder_path, string textpack_path) {
        return FileExporter.export_textpack (folder_path, textpack_path);
    }

    // Export a pre-built markdown string as a TextPack (.textpack) archive.
    // Finds locally referenced images relative to base_path, bundles them in assets/,
    // and rewrites image paths in the markdown to point to assets/<filename>.
    // Set is_fountain to true when the content is a Fountain screenplay.
    public bool export_textpack_from_markdown (string markdown_content, string textpack_path, string base_path = "", bool is_fountain = false) {
        return FileExporter.export_textpack_from_markdown (markdown_content, textpack_path, base_path, is_fountain);
    }

    // Import an FDX (Final Draft) file, converting it to Fountain format.
    public void import_fdx (string fdx_path, Sheets parent) {
        FileImporter.import_fdx (fdx_path, parent);
    }

    public class FileLock : Object {
        public FileLock () {
            FileManager.acquire_lock ();
        }

        ~FileLock () {
            FileManager.release_lock ();
        }
    }

    public static void acquire_lock () {
        //
        // Bad locking, but wait if we're doing file switching already
        //
        // Misbehave after ~4 seconds of waiting...
        //
        int tries = 0;
        while (disable_save && tries < 15) {
            Thread.usleep(250);
            tries++;
        }

        if (tries == 15) {
            warning ("*** Broke out ***");
        }

        debug ("*** Lock acq");

        disable_save = true;
    }

    public static void release_lock () {
        disable_save = false;

        debug ("*** Lock rel");
    }
}
