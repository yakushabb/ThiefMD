/*
 * Copyright (C) 2021 kmwallio
 * 
 * Modified March 21, 2021
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
using ThiefMD.Controllers;
using ThiefMD.Widgets;

namespace ThiefMD.Enrichments {
    public class GrammarUpdateRequest {
        public int cursor_offset;
        public int text_offset;
        public string text;
        public Gee.List<string> words;

        public GrammarUpdateRequest () {
            words = new Gee.LinkedList<string> ();
        }

        public static int compare_tag_requests (GrammarUpdateRequest a, GrammarUpdateRequest b) {
            if ((a.cursor_offset == b.cursor_offset) &&
                (a.text_offset == b.text_offset) &&
                (a.text == b.text))
            {
                return 0;
            }

            if (a.text != b.text) {
                return strcmp (a.text, b.text);
            }

            if (a.text_offset != b.text_offset) {
                return a.text_offset - b.text_offset;
            }

            if (a.cursor_offset != b.cursor_offset) {
                return a.cursor_offset - b.cursor_offset;
            }

            // Tags are different?
            return -1;
        }
    }

    public class GrammarChecker {
        // TextView to attach to and buffer of view
        private Gtk.TextView view;
        private Gtk.TextBuffer buffer;

        // Mutex to prevent multiple scans at same time
        private Mutex checking;

        // Timer between when checks can run
        private TimedMutex limit_updates;

        // Class for scanning setences for grammar,
        // we do this to have watchdog thread to kill
        // link-parser if taking too long
        private GrammarThinking checker;

        // Tags to style grammar errors
        public Gtk.TextTag grammar_line;
        public Gtk.TextTag grammar_word;

        // Last place cursor was in the previous run to
        // scan sentences around it as well as new cursor location
        private int last_cursor;

        // Threading State
        private Thread<void> grammar_processor;
        private Mutex processor_check;
        private bool processor_running;
        private Gee.ConcurrentSet<GrammarUpdateRequest> send_to_processor;
        private Gee.ConcurrentSet<GrammarUpdateRequest> send_to_buffer;

        public GrammarChecker () {
            checking = Mutex ();

            // Default to allow scanning every 2 seconds
            limit_updates = new TimedMutex (2000);
            grammar_line = null;
            grammar_word = null;
            last_cursor = -1;
            checker = new GrammarThinking ();
            processor_check = Mutex ();
            processor_running = false;
            grammar_processor = null;
            send_to_processor = new Gee.ConcurrentSet<GrammarUpdateRequest> (GrammarUpdateRequest.compare_tag_requests);
            send_to_buffer = new Gee.ConcurrentSet<GrammarUpdateRequest> (GrammarUpdateRequest.compare_tag_requests);
        }

        /**
        * reset ()
        * Reset scan area and grammar check entire document
        */
        public void reset () {
            last_cursor = -1;
            recheck_all ();
        }

        /**
        * recheck_all ()
        * Rechecks all sentences around cursor (see what I did there...?)
        * Scans previous cursor location to attempt to keep whole document
        * up to date.
        */
        public void recheck_all () {
            if (view == null || buffer == null) {
                return;
            }

            if (!limit_updates.can_do_action ()) {
                return;
            }

            if (!checking.trylock ()) {
                return;
            }

            // Remove any previous tags
            Gtk.TextIter start, end, cursor_iter;
            var cursor = buffer.get_insert ();
            buffer.get_iter_at_mark (out cursor_iter, cursor);
            int current_cursor = cursor_iter.get_offset ();

            // If last cursor isn't set, scan whole doc
            if (last_cursor == -1) {
                //  Thinking worker = new Thinking (
                //      _("Checking Grammar"),
                //      () => {
                //          Gtk.TextIter t_start, t_end;
                //          buffer.get_bounds (out t_start, out t_end);
                //          run_between_start_and_end (t_start, t_end);
                //      },
                //      ThiefProperties.GRAMMAR_WINDOW_MESSAGES);
                //  worker.run ();
                Gtk.TextIter t_start, t_end;
                buffer.get_bounds (out t_start, out t_end);
                run_worker_between_start_and_end (t_start, t_end);
            } else {
                //
                // Scan where we are
                //
                buffer.get_iter_at_mark (out start, cursor);
                buffer.get_iter_at_mark (out end, cursor);
                get_chunk_of_text_around_cursor (ref start, ref end, false);
                run_between_start_and_end (start, end);

                //
                // Rescan where we were if still in buffer,
                // and not where we just scanned
                //
                // 60 because some people type sentence per line,
                // Assuming ~6-15 words in a sentence at ~7 characters per word
                // Also need to account for mouse click jumps
                //
                if ((current_cursor - last_cursor).abs () > 60) {
                    Gtk.TextIter old_start, old_end, bound_start, bound_end;
                    buffer.get_bounds (out bound_start, out bound_end);
                    buffer.get_iter_at_offset (out old_start, last_cursor);
                    buffer.get_iter_at_offset (out old_end, last_cursor);
                    if (old_start.in_range (bound_start, bound_end)) {
                        get_chunk_of_text_around_cursor (ref old_start, ref old_end, false);
                        if (!old_start.in_range (start, end) || !old_end.in_range (start, end)) {
                            run_between_start_and_end (old_start, old_end);
                        }
                    }
                }
            }

            last_cursor = current_cursor;
            checking.unlock ();
        }

        //
        // Where the magic happens
        //
        private void grab_sentence (ref Gtk.TextIter start, ref Gtk.TextIter end) {
            //
            // Check if we're tagging markdown links and URLs
            //
            var link_tag = buffer.tag_table.lookup ("markdown-link");
            var url_tag = buffer.tag_table.lookup ("markdown-url");

            //
            // Gtk.TextIter determines .end_sentence () based on punctuation. "thiefmd.com"
            // would cause "thief" to be detected as the end of sentence. But, we're in a URL
            // So continue on down, and check for end_sentence not in a URL.
            //
            if (!end.ends_sentence () || ((link_tag != null && end.has_tag (link_tag)) || (url_tag != null && end.has_tag (url_tag)))) {
                do {
                    Gtk.TextIter next_line = end.copy (), next_sentence = end.copy ();
                    if (next_line.forward_to_line_end () && next_sentence.forward_sentence_end () && next_line.get_offset () < next_sentence.get_offset ()) {
                        end.forward_to_line_end ();
                        break;
                    }
                    if (!end.forward_sentence_end ()) {
                        break;
                    }
                } while ((end.has_tag (url_tag) || end.has_tag (link_tag)));
            }

            //
            // We may have found a valid end of sentence, but writers could do:
            // "You're a wizard Harry!"
            // And grammar checking might notice the missing " if not included
            //
            while (!end.get_char ().isspace ()) {
                if (!end.forward_char ()) {
                    break;
                }
            }
        }

        // Check if worker queue is already running. If not,
        // starts the worker thread.
        private void start_worker () {
            processor_check.lock ();
            if (!processor_running) {
                if (grammar_processor != null) {
                    grammar_processor.join ();
                }

                grammar_processor = new Thread<void> ("grammar-processor", process_grammar);
                processor_running = true;
            }
            processor_check.unlock ();
        }

        // Processes the queue to update the buffer if the sentence
        // still matches.
        private bool update_buffer () {
            if (buffer == null) {
                return false;
            }

            Gtk.TextIter buffer_start, buffer_end, cursor_location;
            var cursor = buffer.get_insert ();
            buffer.get_iter_at_mark (out cursor_location, cursor);

            buffer.get_bounds (out buffer_start, out buffer_end);
            while (send_to_buffer.size != 0) {
                GrammarUpdateRequest requested = send_to_buffer.first ();
                send_to_buffer.remove (requested);

                // Check at the offset in the request
                Gtk.TextIter check_start, check_end;
                buffer.get_iter_at_offset (out check_start, requested.text_offset);
                buffer.get_iter_at_offset (out check_end, requested.text_offset + requested.text.length);
                if (check_start.in_range (buffer_start, buffer_end) && 
                    check_end.in_range (buffer_start, buffer_end) && 
                    check_start.get_text (check_end).chug ().chomp () == requested.text)
                {
                    tag_sentence (check_start, check_end, requested.words);
                    continue;
                }

                int cursor_change = cursor_location.get_offset () - requested.cursor_offset;
                if (check_start.forward_chars (cursor_change)) {
                    buffer.get_iter_at_offset (out check_end, check_start.get_offset () + requested.text.length);
                    if (check_start.in_range (buffer_start, buffer_end) && 
                        check_end.in_range (buffer_start, buffer_end) && 
                        check_start.get_text (check_end).chug ().chomp () == requested.text)
                    {
                        tag_sentence (check_start, check_end, requested.words);
                        continue;
                    }
                }
            }

            return true;
        }

        private void process_grammar () {
            if (buffer == null) {
                return;
            }

            while (send_to_processor.size != 0) {
                GrammarUpdateRequest requested = send_to_processor.first ();
                send_to_processor.remove (requested);
                string sentence = strip_markdown (requested.text).chug ().chomp ();
                if (!checker.sentence_check (sentence, requested.words)) {
                    send_to_buffer.add (requested);
                }
            }
            processor_running = false;
            Thread.exit (0);
            return;
        }

        //
        // run_worker_between_start_and_end (Gtk.TextIter start, Gtk.TextIter end)
        // Scans for sentences and requests the worker to process in a separate thread.
        //
        private void run_worker_between_start_and_end (Gtk.TextIter start, Gtk.TextIter end) {
            if (grammar_word == null || grammar_line == null) {
                return;
            }

            // Okay, we lied. Try to make sure the start starts at the start of a sentence
            if (!start.starts_sentence ()) {
                start.backward_sentence_start ();
            }

            // We move backward because forward could grab more lines
            if (!end.ends_sentence ()) {
                end.backward_sentence_start ();
            }

            // Make sure we have something to grab
            if (end.get_offset () == start.get_offset ()) {
                return;
            }

            // Remove grammar tags between scan area
            buffer.remove_tag (grammar_line, start, end);
            buffer.remove_tag (grammar_word, start, end);

            // Grab the first sentence and move the end iterator
            Gtk.TextIter check_end = start;
            grab_sentence (ref start, ref check_end);
            Gtk.TextIter check_start = start;

            // So we don't grammar check in code
            var code_block = buffer.tag_table.lookup ("code-block");

            // Where something not quite as magical happens...
            // loop over every sentence in range.
            while (check_start.in_range (start, end) &&
                    check_end.in_range (start, end) &&
                    (check_end.get_offset () != check_start.get_offset ())) 
            {
                Gtk.TextIter cursor_iter;
                var cursor = buffer.get_insert ();
                buffer.get_iter_at_mark (out cursor_iter, cursor);

                // If the cursor is in the sentence, don't tell the user their possibly
                // incomplete sentence is grammatically incorrect. It's in progress, mmkay?
                //
                // Also make sure we're not in a code block.
                if ((!cursor_iter.in_range (check_start, check_end)) &&
                    (!(code_block != null && (check_start.has_tag (code_block) || check_end.has_tag (code_block)))))
                {
                    // Grab the sentence and prep for problem word tagging
                    string sentence = buffer.get_text (check_start, check_end, false).chug ().chomp ();
                    // Only run on full sentences
                    if (sentence != "") {
                        GrammarUpdateRequest request = new GrammarUpdateRequest () {
                            cursor_offset = cursor_iter.get_offset (),
                            text_offset = check_start.get_offset (),
                            text = sentence
                        };
                        send_to_processor.add (request);
                    }
                }

                // Move along to the next sentence (if possible)
                check_start = check_end;
                check_start.forward_char ();
                if (!check_end.forward_sentence_end ()) {
                    break;
                }
                grab_sentence (ref check_start, ref check_end);
            }

            start_worker ();
        }

        //
        // run_between_start_and_end (Gtk.TextIter start, Gtk.TextIter end)
        // Scans for sentences and runs grammar checking on the sentences between
        // the start and end TextIters.
        //
        private void run_between_start_and_end (Gtk.TextIter start, Gtk.TextIter end) {
            if (grammar_word == null || grammar_line == null) {
                return;
            }

            // Okay, we lied. Try to make sure the start starts at the start of a sentence
            if (!start.starts_sentence ()) {
                start.backward_sentence_start ();
            }

            // We move backward because forward could grab more lines
            if (!end.ends_sentence ()) {
                end.backward_sentence_start ();
            }

            // Make sure we have something to grab
            if (end.get_offset () == start.get_offset ()) {
                return;
            }

            // Remove grammar tags between scan area
            buffer.remove_tag (grammar_line, start, end);
            buffer.remove_tag (grammar_word, start, end);

            // Grab the first sentence and move the end iterator
            Gtk.TextIter check_end = start;
            grab_sentence (ref start, ref check_end);
            Gtk.TextIter check_start = start;

            // So we don't grammar check in code
            var code_block = buffer.tag_table.lookup ("code-block");

            // Where something not quite as magical happens...
            // loop over every sentence in range.
            while (check_start.in_range (start, end) &&
                    check_end.in_range (start, end) &&
                    (check_end.get_offset () != check_start.get_offset ())) 
            {
                Gtk.TextIter cursor_iter;
                var cursor = buffer.get_insert ();
                buffer.get_iter_at_mark (out cursor_iter, cursor);

                // If the cursor is in the sentence, don't tell the user their possibly
                // incomplete sentence is grammatically incorrect. It's in progress, mmkay?
                //
                // Also make sure we're not in a code block.
                if ((!cursor_iter.in_range (check_start, check_end)) &&
                    (!(code_block != null && (check_start.has_tag (code_block) || check_end.has_tag (code_block)))))
                {
                    // Grab the sentence and prep for problem word tagging
                    string sentence = buffer.get_text (check_start, check_end, false).chug ().chomp ();
                    Gee.List<string> problem_words = new Gee.LinkedList<string> ();
                    // Only run on full sentences
                    if (sentence != "" && !checker.sentence_check (sentence, problem_words)) {
                        tag_sentence (check_start, check_end, problem_words);
                    }
                }

                // Move along to the next sentence (if possible)
                check_start = check_end;
                check_start.forward_char ();
                if (!check_end.forward_sentence_end ()) {
                    break;
                }
                grab_sentence (ref check_start, ref check_end);
            }
        }

        //
        // handle_tooltip (...)
        //
        // Check if mouse is over a grammatically incorrect sentence, and if so
        // show the error string representation of the grammar checker because people
        // who didn't code this will totally understand how to interpret it...
        //
        public bool handle_tooltip (int x, int y, bool keyboard_tooltip, Gtk.Tooltip tooltip) {
            Gtk.TextIter? iter;

            // Determine if user requested a tooltip via mouse or keyboard
            if (keyboard_tooltip) {
                int offset = buffer.cursor_position;
                buffer.get_iter_at_offset (out iter, offset);
            } else {
                int m_x, m_y, trailing;
                view.window_to_buffer_coords (Gtk.TextWindowType.TEXT, x, y, out m_x, out m_y);
                view.get_iter_at_position (out iter, out trailing, m_x, m_y);
            }

            if (iter != null) {
                if (iter.has_tag (grammar_line)) {
                    // Find the sentence the user is hovered over or in
                    Gtk.TextIter start = iter.copy (), end = iter.copy ();
                    bool no_foward = false;
                    while (start.has_tag (grammar_line)) {
                        if (!start.backward_char ()) {
                            no_foward = true;
                            break;
                        }
                    }
                    if (!no_foward) {
                        start.forward_char ();
                    }
                    no_foward = false;
                    while (end.has_tag (grammar_line)) {
                        if (!end.forward_char ()) {
                            no_foward = true;
                            break;
                        }
                    }
                    if (!no_foward) { // lol, variable reuse
                        end.backward_char ();
                    }
                    string suggestion = "";

                    // Run the checker over the sentence to and show raw suggestion output
                    if (!checker.sentence_check_suggestion (strip_markdown (buffer.get_text (start, end, false)), out suggestion) && suggestion != "") {
                        tooltip.set_markup (suggestion.replace ("&", "&amp;"));
                        return true; // Don't try to find other tooltips
                    }
                }
            } else {
                return false; // I got nothing for you, see if someone else has a tooltip
            }

            return false;
        }

        private void tag_sentence (Gtk.TextIter check_start, Gtk.TextIter check_end, Gee.List<string> problem_words) {
            while (check_start.get_char () == ' ' && check_start.forward_char ()) {
                if (check_start.get_char () != ' ') {
                    break;
                }
            }

            // Highlight error line
            buffer.apply_tag (grammar_line, check_start, check_end);
            Gtk.TextIter word_start = check_start.copy ();
            Gtk.TextIter word_end = check_start.copy ();

            // If we have words we can highlight, highlight them.
            // Sadly note, we do not highlight punctuation, we also highlight
            // multiple occurrences of a matchin word even though one instance
            // may be incorrect
            if (!problem_words.is_empty) {
                while (word_end.forward_word_end () && word_end.get_offset () <= check_end.get_offset ()) {
                    // Grab the word in the sentence and try to make it as basic as possible
                    string check_word = strip_markdown (word_start.get_text (word_end)).chug ().chomp ();
                    check_word = check_word.replace ("\"", "");

                    // Check if the word is in the list of problematic words
                    if (problem_words.contains (check_word) || // what's coding style?
                        problem_words.contains (check_word.down ()))
                    {
                        // Strip whitespace in iter
                        while ((word_start.get_char () == ' ' || word_start.get_char () == '#' ||
                                word_start.get_char () == '>' || word_start.get_char () == '-') &&
                                word_start.forward_char ())
                        {
                            if (word_start.get_char () != ' ' && word_start.get_char () != '#' &&
                                word_start.get_char () != '>' && word_start.get_char () != '-')
                            {
                                break;
                            }
                        }
                        buffer.apply_tag (grammar_word, word_start, word_end);
                    }
                    word_start = word_end;
                }
            }
        }

        //
        // attach (Gtk.TextView textview)
        //
        // Attach to the view in a similar style like Gtk.Spell.
        //
        public bool attach (Gtk.TextView textview) {
            if (textview == null) {
                return false;
            }

            view = textview;
            buffer = textview.get_buffer ();

            if (buffer == null) {
                view = null;
                return false;
            }

            grammar_line = buffer.create_tag ("grammar_check", "underline", Pango.Underline.ERROR, null);
            grammar_line.underline_rgba = Gdk.RGBA () { red = 0.0, green = 0.40, blue = 0.133, alpha = 1.0 };

            grammar_word = buffer.create_tag ("grammar_word", "underline", Pango.Underline.ERROR, null);
            grammar_word.underline_rgba = Gdk.RGBA () { red = 0.0, green = 0.40, blue = 0.133, alpha = 1.0 };
            grammar_word.background_rgba = Gdk.RGBA () { red = 0.0, green = 0.40, blue = 0.133, alpha = 1.0 };
            grammar_word.foreground_rgba = Gdk.RGBA () { red = 0.9, green = 0.9, blue = 0.9, alpha = 1.0 };
            grammar_word.background_set = true;
            grammar_word.foreground_set = true;
            checker.check_language_settings ();

            view.set_has_tooltip (true);
            view.query_tooltip.connect (handle_tooltip);

            last_cursor = -1; // reset to scan whole document on attach

            GLib.Idle.add (update_buffer);
            ThiefApp.get_instance ().destroy.connect (detach);

            return true;
        }

        //
        // detach ()
        //
        // Detach from view and remove all references to view.
        //
        // Cache will not be cleared.
        //
        public void detach () {
            // Drain queues
            while (send_to_buffer.size != 0) {
                GrammarUpdateRequest requested = send_to_buffer.first ();
                send_to_buffer.remove (requested);
            }
            while (send_to_processor.size != 0) {
                GrammarUpdateRequest requested = send_to_processor.first ();
                send_to_processor.remove (requested);
            }
            if (grammar_processor != null) {
                grammar_processor.join ();
            }
            ThiefApp.get_instance ().destroy.disconnect (detach);

            if (buffer == null) {
                return;
            }

            Gtk.TextIter start, end;
            buffer.get_bounds (out start, out end);

            buffer.remove_tag (grammar_line, start, end);
            buffer.remove_tag (grammar_word, start, end);
            buffer.tag_table.remove (grammar_line);
            buffer.tag_table.remove (grammar_word);

            view.query_tooltip.disconnect (handle_tooltip);

            grammar_line = null;
            grammar_word = null;

            view = null;
            buffer = null;
            last_cursor = -1;
        }
    }

    //
    // Class for running `link-parser` with timing constraints
    //
    public class GrammarThinking : GLib.Object {
        // Time we are willing to wait and signal to cancel
        private int wait_time;
        private Cancellable cancellable;

        // Variable to let watchdog know everything is fine...
        private bool done;

        // Sentence caches so if we scan while user is typing,
        // it seems magically fast and non-disruptive.
        private Gee.LinkedList<string> valid_cache;
        private Gee.LinkedList<string> invalid_cache;
        private Gee.LinkedList<string> invalid_suggestion;

        // Max size of valid sentences to keep.
        // Invalid = cache_size / 2 because we hope people fix it
        // and sentences are more likely to change due to errors being
        // fixed.
        private int cache_size;
        private string language;

        public GrammarThinking (int cache_items = Constants.GRAMMAR_SENTENCE_CACHE_SIZE, int timeout_millseconds = Constants.GRAMMAR_SENTENCE_CHECK_TIMEOUT) {
            wait_time = timeout_millseconds;
            cache_size = cache_items;
            valid_cache = new Gee.LinkedList<string> ();
            invalid_cache = new Gee.LinkedList<string> ();
            invalid_suggestion = new Gee.LinkedList<string> ();
            check_language_settings ();
        }

        //
        // Look at spellcheck settings, and attempt to use that.
        //
        public void check_language_settings () {
            language = "en";
            var settings = AppSettings.get_default ();
            // @TODO could check file path and if this changes sometime
            if (settings.spellcheck_language.length > 2) {
                language = settings.spellcheck_language.substring (0, 2);
                if (!language_check (language)) {
                    language = "";
                }
            }
        }

        // If we have a language we could use
        public bool language_detected () {
            return language != "";
        }

        // Keep caches within condigured range
        private void resize_cache () {
            while (valid_cache.size > cache_size) {
                valid_cache.poll ();
            }
            while (invalid_cache.size > (cache_size / 2)) {
                invalid_cache.poll ();
                invalid_suggestion.poll ();
            }
        }

        // Empty the caches
        public void clear_cache () {
            while (!valid_cache.is_empty) {
                valid_cache.poll ();
            }
            while (!invalid_cache.is_empty) {
                invalid_cache.poll ();
                invalid_suggestion.poll ();
            }
        }

        // Need to figure out how to do this in flatpak and native
        // But currently check to see if `link-parser` is able to load
        // the dictionary.
        public bool language_check (string lang) {
            bool have_language = false;
            bool res = false;
            done = false;

            Subprocess grammar;
            InputStream? output_stream = null;
            try {
                cancellable = new Cancellable ();
                string[] command = {
                    "link-parser",
                    lang,
                    "-batch"
                };
                grammar = new Subprocess.newv (command,
                    SubprocessFlags.STDOUT_PIPE |
                    SubprocessFlags.STDIN_PIPE |
                    SubprocessFlags.STDERR_MERGE);

                var input_stream = grammar.get_stdin_pipe ();
                if (input_stream != null) {
                    DataOutputStream flush_buffer = new DataOutputStream (input_stream);
                    if (!flush_buffer.put_string ("thief were here")) {
                        warning ("Could not set buffer");
                    }
                    flush_buffer.flush ();
                    flush_buffer.close ();
                }
                output_stream = grammar.get_stdout_pipe ();

                // Before we wait, setup watchdogs
                Thread<void> watchdog = null;
                if (Thread.supported ()) {
                    watchdog = new Thread<void> ("grammar_watchdog", this.watch_dog);
                } else {
                    int now = 0;
                    Timeout.add (5, () => {
                        now += 5;
                        if (now > wait_time && !done) {
                            cancellable.cancel ();
                        }
                        return done;
                    });
                }

                res = grammar.wait (cancellable);
                done = true;
                if (watchdog != null) {
                    watchdog.join ();
                }
            } catch (Error e) {
                warning ("Failed to run grammar: %s", e.message);
            }

            try {
                if (output_stream != null) {
                    var proc_input = new DataInputStream (output_stream);
                    string line = "";
                    while ((line = proc_input.read_line (null)) != null) {
                        line = line.down ();
                        have_language = have_language || line.contains ("dictionary found");
                    }
                }
            } catch (Error e) {
                warning ("Could not process output: %s", e.message);
            }

            return have_language;
        }

        // Check if sentence is valid or not, and get the raw error string
        public bool sentence_check_suggestion (string sentence, out string suggestion) {
            return sentence_check_ex (sentence, out suggestion);
        }

        // Check if sentence if valid or not, and get a list of problem words
        public bool sentence_check (string sentence, Gee.List<string>? problem_words = null) {
            string suggestion;
            return sentence_check_ex (sentence, out suggestion, problem_words);
        }

        // Convert the raw output of link parser into a suggestion string and a list of possible issues
        private void parse_suggestion (string raw_suggestion, out string suggestion, Gee.List<string>? problem_words = null) {
            suggestion = "";
            string[] parts = raw_suggestion.replace ("LEFT-WALL", "").replace ("RIGHT-WALL", "").replace ("  ", " ").chug ().chomp ().split (" ");
            string last_word = "";
            foreach (var word in parts) {
                if (problem_words != null && word.has_prefix ("[")) {
                    string problem_word = word.substring (1, word.index_of_char (']') - 1);
                    if (problem_word.has_prefix ("'") || problem_word.has_prefix (",") || problem_word.has_prefix (".") ||
                        problem_word.has_prefix ("?") || problem_word.has_prefix ("?"))
                    {
                        problem_word = last_word + problem_word;
                    }
                    if (problem_word != "") {
                        problem_words.add (problem_word);
                    }
                }

                if (word.index_of_char ('.') != -1) {
                    word = word.substring (0, word.index_of_char ('.'));
                }
                last_word = word;
                suggestion += word + " ";
            }
        }

        // If there's a cache hit, this'll grab the item from the cache.
        private bool grab_invalid_suggestion (string sentence, out string suggestion, Gee.List<string>? problem_words = null) {
            int index = invalid_cache.index_of (sentence);
            if (index != -1) {
                parse_suggestion (invalid_suggestion.get (index), out suggestion, problem_words);
            } else {
                suggestion = "";
            }
            return false;
        }

        // Check grammar in a sentence
        public bool sentence_check_ex (string sentence, out string suggestion, Gee.List<string>? problem_words = null) {
            suggestion = "";
            if (valid_cache.contains (sentence)) {
                return true;
            }

            if (invalid_cache.contains (sentence)) {
                return grab_invalid_suggestion (sentence, out suggestion, problem_words);
            }

            if (language == "") {
                return true;
            }

            bool error_free = false;
            bool res = false;
            done = false;
            string raw_suggestion = "";
            string check_sentence = strip_markdown (sentence).chug ().chomp ();
            // If it looks like we'd be noisy for HTML or random syntax
            if (check_sentence.contains ("[") || check_sentence.contains ("]") ||
                sentence.contains ("<") || sentence.contains (">") || sentence.has_prefix ("!") ||
                sentence.replace ("-", "").chug ().chomp () == "" || sentence.replace ("*", "").chug ().chomp () == "")
            {
                return true;
            }

            InputStream? output_stream = null;

            try {
                cancellable = new Cancellable ();
                string[] command = {
                    "link-parser",
                    language
                };
                Subprocess grammar = new Subprocess.newv (command,
                    SubprocessFlags.STDOUT_PIPE |
                    SubprocessFlags.STDIN_PIPE |
                    SubprocessFlags.STDERR_MERGE);

                var input_stream = grammar.get_stdin_pipe ();
                if (input_stream != null) {
                    DataOutputStream flush_buffer = new DataOutputStream (input_stream);
                    if (!flush_buffer.put_string (check_sentence)) {
                        warning ("Could not set buffer");
                    }
                    flush_buffer.flush ();
                    flush_buffer.close ();
                }
                output_stream = grammar.get_stdout_pipe ();

                // Before we wait, setup watchdogs
                Thread<void> watchdog = null;
                if (Thread.supported ()) {
                    watchdog = new Thread<void> ("grammar_watchdog", this.watch_dog);
                } else {
                    int now = 0;
                    Timeout.add (5, () => {
                        now += 5;
                        if (now > wait_time && !done) {
                            cancellable.cancel ();
                        }
                        return done;
                    });
                }

                res = grammar.wait (cancellable);
                done = true;
                if (watchdog != null) {
                    watchdog.join ();
                }
            } catch (Error e) {
                warning ("Failed to run grammar: %s", e.message);
                error_free = true;
            }

            // output scan in separate try in case process gets killed
            // killed process winds up in the first catch. It's possible
            // STDOUT could have some output.
            try {
                if (output_stream != null) {
                    var proc_input = new DataInputStream (output_stream);
                    string line = "";
                    while ((line = proc_input.read_line (null)) != null) {
                        line = line.chomp ().chug ();
                        error_free = error_free || line.down ().contains ("unused=0");
                        if (line.has_prefix ("LEFT-WALL")) {
                            raw_suggestion = line;
                            parse_suggestion (raw_suggestion, out suggestion, problem_words);
                        }
                    }
                } else {
                    warning ("Got nothing");
                }

                if (!res || output_stream == null) {
                    error_free = true;
                }
            } catch (Error e) {
                warning ("Could not process output: %s", e.message);
            }

            // We got here meaning we processed something or we won't be able to process
            // the output if passed it again.
            // Cache the result.
            if (error_free) {
                valid_cache.add (sentence);
                resize_cache ();
            }
            if (!error_free && raw_suggestion != "") {
                invalid_cache.add (sentence);
                invalid_suggestion.add (raw_suggestion);
                resize_cache ();
            }

            return error_free;
        }

        // Watchdog just hangs out until we need to terminate the
        // process or bails out.
        private void watch_dog () {
            int now = 0;
            while (now < wait_time && !done) {
                Thread.usleep (5000);
                now += 5;
            }

            if (!done) {
                cancellable.cancel ();
                warning ("Had to terminate grammar");
            }

            Thread.exit (0);
            return;
        }
    }
}