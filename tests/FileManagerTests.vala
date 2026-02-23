using ThiefMD;
using ThiefMD.Controllers;
using ThiefMD.Widgets;

public class FileManagerTests {
    public FileManagerTests () {
        Test.add_func ("/thiefmd/file_open_tests", () => {
            string readme = Pandoc.find_file ("README.md", Environment.get_current_dir ());
            assert (readme != "");
            assert (readme != "README.md");
            Editor editor;
            FileManager.open_file (readme, out editor);
            assert (editor != null);
            FileManager.open_file ("basdfasdfasdfjawlekrthasjkldhfgajklsdhflkasjd.md", out editor);
            assert (editor == null);

            string readme_contents = FileManager.get_file_contents (readme);
            assert (readme_contents != "");
            string title, date;
            string untouched = FileManager.get_file_lines_yaml (
                readme, // File
                4, // read all lines
                false, // include empty lines
                out title,
                out date);

            assert (untouched != "");
            assert (title != "");
            assert (title.down ().contains ("thief"));
        });

        Test.add_func ("/thiefmd/textpack_export", () => {
            // Set up a temp folder with some markdown files
            string temp_dir = DirUtils.make_tmp ("thiefmd_textpack_XXXXXX");
            string md1 = Path.build_filename (temp_dir, "chapter1.md");
            string md2 = Path.build_filename (temp_dir, "chapter2.md");
            string textpack_path = Path.build_filename (temp_dir, "output.textpack");

            try {
                FileUtils.set_contents (md1, "# Chapter 1\n\nOnce upon a time...\n");
                FileUtils.set_contents (md2, "# Chapter 2\n\nAnd they all lived happily ever after.\n");

                // Export the folder as a textpack
                bool success = FileManager.export_textpack (temp_dir, textpack_path);
                assert (success);
                assert (File.new_for_path (textpack_path).query_exists ());

                // Verify the textpack contains the right files
                var archive = new Archive.Read ();
                archive.support_filter_all ();
                archive.support_format_all ();
                archive.open_filename (textpack_path, 10240);

                bool found_info = false;
                bool found_text = false;
                unowned Archive.Entry entry;
                while (archive.next_header (out entry) == Archive.Result.OK) {
                    if (entry.pathname () == "info.json") {
                        found_info = true;
                    }
                    if (entry.pathname () == "text.md") {
                        found_text = true;
                    }
                    archive.read_data_skip ();
                }
                archive.close ();

                assert (found_info);
                assert (found_text);
            } catch (Error e) {
                warning ("textpack_export test failed: %s", e.message);
                assert_not_reached ();
            }

            // Clean up temp folder
            try {
                Dir cleanup_dir = Dir.open (temp_dir, 0);
                string? cleanup_name = null;
                while ((cleanup_name = cleanup_dir.read_name ()) != null) {
                    string cleanup_path = Path.build_filename (temp_dir, cleanup_name);
                    if (FileUtils.test (cleanup_path, FileTest.IS_DIR)) {
                        DirUtils.remove (cleanup_path);
                    } else {
                        FileUtils.unlink (cleanup_path);
                    }
                }
                DirUtils.remove (temp_dir);
            } catch (Error e) {
                warning ("Could not clean up temp folder: %s", e.message);
            }
        });

        Test.add_func ("/thiefmd/bear2bk_import", () => {
            // Create a tiny bear2bk archive in /tmp for this test
            string archive_path = Path.build_filename (
                Environment.get_tmp_dir (),
                "thiefmd-bear2bk-test.bear2bk"
            );
            string dest = Path.build_filename (
                Environment.get_tmp_dir (),
                "thiefmd-bear2bk-dest"
            );

            // Use python3 to build a valid zip/bear2bk archive
            string script =
                "import zipfile\n" +
                "z = zipfile.ZipFile('" + archive_path + "', 'w')\n" +
                // Note references the asset via assets/ prefix (as Bear.app exports it)
                "z.writestr('My First Note.textbundle/text.md', '# Hello World\\n\\n![img](assets/image.png)\\n')\n" +
                "z.writestr('My First Note.textbundle/assets/image.png', 'PNG')\n" +
                "z.writestr('Another Note.textbundle/text.md', '# Another Note\\n')\n" +
                "z.close()\n";

            try {
                string[] cmd = { "python3", "-c", script };
                int status;
                Process.spawn_sync (null, cmd, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            } catch (SpawnError e) {
                warning ("Could not build bear2bk fixture, skipping: %s", e.message);
                return;
            }

            if (!FileUtils.test (archive_path, FileTest.EXISTS)) {
                warning ("bear2bk fixture not created, skipping test");
                return;
            }

            // Make a clean destination directory
            File dest_dir = File.new_for_path (dest);
            if (!dest_dir.query_exists ()) {
                try {
                    dest_dir.make_directory_with_parents ();
                } catch (Error e) {
                    assert_not_reached ();
                }
            }

            // extract_bear2bk is the pure extraction helper (testable without Sheets)
            FileManager.extract_bear2bk (archive_path, dest);

            // Both notes should land as .md files
            assert (FileUtils.test (Path.build_filename (dest, "My First Note.md"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (dest, "Another Note.md"), FileTest.EXISTS));

            // The note content should be readable markdown
            string note1 = FileManager.get_file_contents (Path.build_filename (dest, "My First Note.md"));
            assert (note1.contains ("Hello World"));

            // The asset from the first note should be extracted under assets/
            assert (FileUtils.test (Path.build_filename (dest, "assets", "image.png"), FileTest.EXISTS));

            // The markdown image path should remain as "assets/image.png"
            assert (note1.contains ("assets/image.png"));
        });

        Test.add_func ("/thiefmd/extract_files_url_decoded_match", () => {
            string archive_path = Path.build_filename (
                Environment.get_tmp_dir (),
                "thiefmd-path-match-test.zip"
            );
            string dest = Path.build_filename (
                Environment.get_tmp_dir (),
                "thiefmd-path-match-dest"
            );

            string script =
                "import zipfile\n" +
                "z = zipfile.ZipFile('" + archive_path + "', 'w')\n" +
                "z.writestr('word/media/My Image.png', 'PNG')\n" +
                "z.close()\n";

            try {
                string[] cmd = { "python3", "-c", script };
                int status;
                Process.spawn_sync (null, cmd, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            } catch (SpawnError e) {
                warning ("Could not build URL decode fixture, skipping: %s", e.message);
                return;
            }

            if (!FileUtils.test (archive_path, FileTest.EXISTS)) {
                warning ("URL decode fixture not created, skipping test");
                return;
            }

            File dest_dir = File.new_for_path (dest);
            if (!dest_dir.query_exists ()) {
                try {
                    dest_dir.make_directory_with_parents ();
                } catch (Error e) {
                    assert_not_reached ();
                }
            }

            var files = new Gee.LinkedList<string> ();
            // Markdown often carries URL-encoded paths.
            files.add ("word/media/My%20Image.png");

            FileManager.extract_files_to_dest (archive_path, files, dest);

            // Keep extracted file path as requested path while matching decoded archive path.
            assert (FileUtils.test (Path.build_filename (dest, "word", "media", "My%20Image.png"), FileTest.EXISTS));
        });

        Test.add_func ("/thiefmd/maybe_url_decode", () => {
            string encoded = "assets/My%20Image%20(1).png";
            string decoded = FileManager.maybe_url_decode (encoded);
            assert (decoded == "assets/My Image (1).png");

            string plain = "assets/image.png";
            assert (FileManager.maybe_url_decode (plain) == plain);

            // Invalid escapes should return the original input unchanged.
            string broken = "assets/My%2Image.png";
            assert (FileManager.maybe_url_decode (broken) == broken);
        });

        Test.add_func ("/thiefmd/textpack_import_extension", () => {
            assert (FileManager.textpack_import_extension ("text.fountain", "movie.textpack") == ".fountain");
            assert (FileManager.textpack_import_extension ("text.fou", "movie.textpack") == ".fountain");

            // Highland files should keep screenplay semantics even when entry is markdown.
            assert (FileManager.textpack_import_extension ("text.markdown", "movie.highland") == ".fountain");
            assert (FileManager.textpack_import_extension ("text.md", "movie.highland") == ".fountain");

            // Regular textpack markdown stays markdown.
            assert (FileManager.textpack_import_extension ("text.markdown", "notes.textpack") == ".md");
            assert (FileManager.textpack_import_extension ("text.md", "notes.textpack") == ".md");
        });

        Test.add_func ("/thiefmd/bear2bk_blocks_path_traversal", () => {
            string archive_path = Path.build_filename (
                Environment.get_tmp_dir (),
                "thiefmd-bear2bk-escape-test.bear2bk"
            );
            string dest = Path.build_filename (
                Environment.get_tmp_dir (),
                "thiefmd-bear2bk-escape-dest"
            );
            string outside_probe = Path.build_filename (Environment.get_tmp_dir (), "thiefmd-bear2bk-escape-probe.png");

            if (FileUtils.test (outside_probe, FileTest.EXISTS)) {
                FileUtils.unlink (outside_probe);
            }

            string script =
                "import zipfile\n" +
                "z = zipfile.ZipFile('" + archive_path + "', 'w')\n" +
                "z.writestr('Safe Note.textbundle/text.md', '# Safe\\n')\n" +
                "z.writestr('Safe Note.textbundle/assets/ok.png', 'OK')\n" +
                "z.writestr('Safe Note.textbundle/assets/../../thiefmd-bear2bk-escape-probe.png', 'BAD')\n" +
                "z.close()\n";

            try {
                string[] cmd = { "python3", "-c", script };
                int status;
                Process.spawn_sync (null, cmd, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            } catch (SpawnError e) {
                warning ("Could not build traversal fixture, skipping: %s", e.message);
                return;
            }

            File dest_dir = File.new_for_path (dest);
            if (!dest_dir.query_exists ()) {
                try {
                    dest_dir.make_directory_with_parents ();
                } catch (Error e) {
                    assert_not_reached ();
                }
            }

            FileManager.extract_bear2bk (archive_path, dest);

            assert (FileUtils.test (Path.build_filename (dest, "Safe Note.md"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (dest, "assets", "ok.png"), FileTest.EXISTS));
            assert (!FileUtils.test (outside_probe, FileTest.EXISTS));
        });

        Test.add_func ("/thiefmd/extract_files_blocks_path_traversal", () => {
            string archive_path = Path.build_filename (
                Environment.get_tmp_dir (),
                "thiefmd-extract-escape-test.zip"
            );
            string dest = Path.build_filename (
                Environment.get_tmp_dir (),
                "thiefmd-extract-escape-dest"
            );
            string outside_probe = Path.build_filename (Environment.get_tmp_dir (), "thiefmd-extract-escape-probe.png");

            if (FileUtils.test (outside_probe, FileTest.EXISTS)) {
                FileUtils.unlink (outside_probe);
            }

            string script =
                "import zipfile\n" +
                "z = zipfile.ZipFile('" + archive_path + "', 'w')\n" +
                "z.writestr('../../thiefmd-extract-escape-probe.png', 'BAD')\n" +
                "z.close()\n";

            try {
                string[] cmd = { "python3", "-c", script };
                int status;
                Process.spawn_sync (null, cmd, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
            } catch (SpawnError e) {
                warning ("Could not build extract traversal fixture, skipping: %s", e.message);
                return;
            }

            File dest_dir = File.new_for_path (dest);
            if (!dest_dir.query_exists ()) {
                try {
                    dest_dir.make_directory_with_parents ();
                } catch (Error e) {
                    assert_not_reached ();
                }
            }

            var files = new Gee.LinkedList<string> ();
            files.add ("../../thiefmd-extract-escape-probe.png");

            FileManager.extract_files_to_dest (archive_path, files, dest);

            assert (!FileUtils.test (outside_probe, FileTest.EXISTS));
        });
    }
}