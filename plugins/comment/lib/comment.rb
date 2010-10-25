
module Redcar
  class Comment
    def self.menus
      Menu::Builder.build do
        sub_menu "Edit" do
          sub_menu "Formatting" do
            item "Toggle Line Comment"     , ToggleLineCommentCommand
            item "Toggle Selection Comment", ToggleSelectionCommentCommand
          end
        end
      end
    end

    def self.storage
      @storage ||=begin
        storage = Plugin::Storage.new('comment_plugin')
        storage.set_default('default_line_comment'       , "//")
        storage.set_default('default_start_block'        , "/*")
        storage.set_default('default_end_block'          , "*/")
        storage.set_default('insert_single_space'        , true)
        storage.set_default('warning_for_using_defaults' , true)
        storage
      end
    end

    def self.comment_map
      @map ||=begin
        c = File.read(Comment.comment_lib_path)
        map = JSON.parse(c)
        Comment.comment_extension_paths.each do |path|
          json = File.read(path)
          JSON.parse(json).each do |item,content|
            map[item] = content
          end
        end
        map
      end
    end

    def self.extensions_file;"comment_extensions.json";end

    def self.comment_lib_path
      File.dirname(__FILE__) + "/../vendor/comment_lib.json"
    end

    def self.comment_extension_paths
      project = Redcar::Project::Manager.focussed_project
      if project
        project.config_files(Comment.extensions_file)
      else
        Dir[File.join(Redcar.user_dir,Comment.extensions_file)]
      end
    end

    def self.keymaps
      osx = Redcar::Keymap.build("main", :osx) do
        link "Cmd+/", ToggleLineCommentCommand
        link "Cmd+.", ToggleSelectionCommentCommand
      end
      linwin = Redcar::Keymap.build("main", [:linux, :windows]) do
        link "Ctrl+/", ToggleLineCommentCommand
        link "Ctrl+.", ToggleSelectionCommentCommand
      end
      [osx, linwin]
    end

    def self.grammar_missing(grammar)
      if Comment.storage['warning_for_using_defaults']
        Application::Dialog.message_box("Comment type not found for #{grammar}. Using defaults instead.") unless @messaged
        @messaged = true
      end
    end

    class ToggleSelectionCommentCommand < Redcar::EditTabCommand
      def execute
        type = Comment.comment_map["#{tab.edit_view.grammar.gsub("\"","")}"]
        if type
          start  = type["start_block"]
          ending = type["end_block"  ]
          return unless start and ending
        else
          Comment.grammar_missing(tab.edit_view.grammar)
          start  = Comment.storage['default_start_block']
          ending = Comment.storage['default_end_block']
        end
        doc.controllers(Redcar::AutoIndenter::DocumentController).first.disable do
          doc.compound do
            if doc.selection?
              text = doc.selected_text
              if text[0,start.split(//).length] == start and
                text[text.split(//).length-ending.split(//).length,text.split(//).length] == ending
                text = text[start.split(//).length,text.split(//).length]
                text = text[0,text.split(//).length-ending.split(//).length]
                doc.replace_selection(text)
              else
                doc.replace_selection("#{start}#{text}#{ending}")
              end
            else
              line                = doc.cursor_line
              text                = doc.get_line_without_end_of_line(line)
              start_idx           = text.index(start)
              end_idx             = text.rindex(ending)
              start_length        = start.split(//).length
              ending_start_offset = text.split(//).length-ending.split(//).length
              if text[0,start_length] == start and text[ending_start_offset,text.split(//).length] == ending
                text = text[start.length,text.split(//).length]
                text = text[0,ending_start_offset]
                doc.replace_line(line,text)
              else
                replacement  = "#{start}#{text}#{ending}"
                replacement += "\n" if doc.get_line(line) =~ /\n$/
                doc.replace_line(line,replacement)
              end
            end
          end
        end
      end
    end

    class ToggleLineCommentCommand < Redcar::EditTabCommand

      def uncomment_and_use_extra_space(end_pos,text)
        if text.split(//).length() >= end_pos+2
          f = text[end_pos+1,end_pos+1]
          p = text[end_pos+2,end_pos+2]
          Comment.storage['insert_single_space'] and
          f =~ /^ / and p !=~ /^ /
        else
          false
        end
      end

      def comment_and_use_extra_space(text)
        unless text.split(//).length() < 1 or
          text[0] == " " or text[0] == "\t"
          Comment.storage['insert_single_space'] and
          text.split(//).length() > 2
        else
          false
        end
      end

	    def execute
        type = Comment.comment_map["#{tab.edit_view.grammar.gsub("\"","")}"]
        if type
          comment = type["line_comment"]
          return unless comment
        else
          Comment.grammar_missing(tab.edit_view.grammar)
          comment = Comment.storage['default_line_comment']
        end
        selected   = doc.selection?
        end_pos    = comment.split(//).length() -1
        range      = doc.selection_range
        start_line = doc.line_at_offset(range.first)
        end_line   = doc.line_at_offset(range.last)
        total_text = "" if selected
        doc.controllers(Redcar::AutoIndenter::DocumentController).first.disable do
          doc.compound do
            (start_line..end_line).each do |line|
              text = doc.get_line(line).chomp
              if text[0..end_pos] == comment
                if uncomment_and_use_extra_space(end_pos,text)
                  text = text[end_pos+2..-1]
                else
                  text = text[end_pos+1..-1]
                end
              else
                if comment_and_use_extra_space(text)
                  text = comment + " " + text
                else
                  text = comment + text
                end
              end
              total_text += text + " " if selected
              doc.replace_line(line, text)
            end
            if selected
              tlength    = total_text.split(//).length() - 1
              offset     = doc.offset_at_line(start_line)
              doc.set_selection_range(offset,offset+tlength)
            end
          end
        end
      end
    end
  end
end