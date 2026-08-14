module Reply
  private struct CharReader
    enum Sequence
      EOF
      UP
      DOWN
      RIGHT
      LEFT
      ENTER
      ESCAPE
      DELETE
      BACKSPACE
      CTRL_A
      CTRL_B
      CTRL_C
      CTRL_D
      CTRL_E
      CTRL_F
      CTRL_K
      CTRL_L
      CTRL_N
      CTRL_P
      CTRL_R
      CTRL_U
      CTRL_V
      CTRL_X
      CTRL_UP
      CTRL_DOWN
      CTRL_LEFT
      CTRL_RIGHT
      CTRL_ENTER
      CTRL_DELETE
      CTRL_BACKSPACE
      ALT_B
      ALT_D
      ALT_F
      ALT_ENTER
      ALT_BACKSPACE
      TAB
      SHIFT_TAB
      SHIFT_ENTER
      HOME
      END
    end

    def initialize(buffer_size = 8192)
      @slice_buffer = Bytes.new(buffer_size)
    end

    def read_char(from io : IO = STDIN)
      nb_read = raw(io, &.read(@slice_buffer))
      parse_escape_sequence(@slice_buffer[0...nb_read])
    end

    # Parse CSI u key sequences (Kitty keyboard protocol), if the app has enabled it.
    #
    # Format: `CSI key_code [; modifier [: event_type]] u`
    # * `modifier` is `1 + bitmask` (shift=1, alt=2, ctrl=4, super=8), so e.g. `6` means
    #   shift+ctrl. It can be more than one digit (up to `16`), so it's parsed as a full
    #   number rather than a single byte.
    # * `event_type` is only present when the app also requested event reporting:
    #   `1` = press (default when absent), `2` = repeat, `3` = release. We treat press and
    #   repeat as the trigger and ignore release, so the shard stays usable even if an app
    #   enables more than plain disambiguation.
    private def handle_kitty_protocol(chars : Bytes) : Sequence?
      return unless chars.size >= 4 &&
                    chars.first? == '\e'.ord &&
                    chars[1]? == '['.ord && chars.last? == 'u'.ord

      body = chars[2...chars.size - 1] # strip leading "ESC [" and trailing "u"
      semi = body.index(';'.ord)

      key_val = String.new(semi ? body[0...semi] : body).to_i32?
      return unless key_val

      return Sequence::ESCAPE if !semi && key_val == 27
      return unless semi

      mod_field = body[(semi + 1)..]
      colon = mod_field.index(':'.ord)
      mod_str = colon ? mod_field[0...colon] : mod_field
      event_str = colon ? mod_field[(colon + 1)..] : nil

      # Ignore key-release events; only press (no event field) and repeat trigger an action.
      return if event_str && String.new(event_str).to_i32? == 3

      key_mod = String.new(mod_str).to_i32?
      return unless key_mod

      # Only combos REPLy already has a shortcut for are mapped here. Anything else (e.g.
      # shift+ctrl, shift+alt+ctrl) falls through to nil and the default fallback below.
      case key_mod
      when 2 # SHIFT
        case key_val
        when '\r'.ord then Sequence::SHIFT_ENTER
        when '\t'.ord then Sequence::SHIFT_TAB
        end
      when 3 # ALT
        case key_val
        when '\r'.ord then Sequence::ALT_ENTER
        when 'd'.ord  then Sequence::ALT_D
        when 0x7f     then Sequence::ALT_BACKSPACE
        end
      when 5 # CTRL
        case key_val
        when '\r'.ord then Sequence::CTRL_ENTER
        when 'a'.ord  then Sequence::CTRL_A
        when 'b'.ord  then Sequence::CTRL_B
        when 'c'.ord  then Sequence::CTRL_C
        when 'd'.ord  then Sequence::CTRL_D
        when 'e'.ord  then Sequence::CTRL_E
        when 'f'.ord  then Sequence::CTRL_F
        when 'k'.ord  then Sequence::CTRL_K
        when 'l'.ord  then Sequence::CTRL_L
        when 'n'.ord  then Sequence::CTRL_N
        when 'p'.ord  then Sequence::CTRL_P
        when 'r'.ord  then Sequence::CTRL_R
        when 'u'.ord  then Sequence::CTRL_U
        when 'v'.ord  then Sequence::CTRL_V
        when 'x'.ord  then Sequence::CTRL_X
        end
      end
    end

    private def parse_escape_sequence(chars : Bytes) : Char | Sequence | String?
      if seq = handle_kitty_protocol(chars)
        return seq
      end

      return String.new(chars) if chars.size > 6
      return Sequence::EOF if chars.empty?

      case chars[0]?
      when '\e'.ord
        case chars[1]?
        when '['.ord
          case chars[2]?
          when 'A'.ord then Sequence::UP
          when 'B'.ord then Sequence::DOWN
          when 'C'.ord then Sequence::RIGHT
          when 'D'.ord then Sequence::LEFT
          when 'Z'.ord then Sequence::SHIFT_TAB
          when '3'.ord
            if {chars[3]?, chars[4]?} == {';'.ord, '5'.ord}
              case chars[5]?
              when '~'.ord then Sequence::CTRL_DELETE
              end
            elsif chars[3]? == '~'.ord
              Sequence::DELETE
            end
          when '1'.ord
            if {chars[3]?, chars[4]?} == {';'.ord, '5'.ord}
              case chars[5]?
              when 'A'.ord then Sequence::CTRL_UP
              when 'B'.ord then Sequence::CTRL_DOWN
              when 'C'.ord then Sequence::CTRL_RIGHT
              when 'D'.ord then Sequence::CTRL_LEFT
              end
            elsif chars[3]? == '~'.ord # linux console HOME
              Sequence::HOME
            end
          when '4'.ord # linux console END
            if chars[3]? == '~'.ord
              Sequence::END
            end
          when 'H'.ord # xterm HOME
            Sequence::HOME
          when 'F'.ord # xterm END
            Sequence::END
          end
        when '\t'.ord
          Sequence::SHIFT_TAB
        when '\r'.ord
          Sequence::ALT_ENTER
        when 0x7f
          Sequence::ALT_BACKSPACE
        when 'O'.ord
          if chars[2]? == 'H'.ord # gnome terminal HOME
            Sequence::HOME
          elsif chars[2]? == 'F'.ord # gnome terminal END
            Sequence::END
          end
        when 'b'
          Sequence::ALT_B
        when 'd'
          Sequence::ALT_D
        when 'f'
          Sequence::ALT_F
        when Nil
          Sequence::ESCAPE
        end
      when '\r'.ord
        Sequence::ENTER
      when '\n'.ord
        {% if flag?(:win32) %}
          Sequence::CTRL_ENTER
        {% else %}
          Sequence::ENTER
        {% end %}
      when '\t'.ord
        Sequence::TAB
      when '\b'.ord
        Sequence::CTRL_BACKSPACE
      when ctrl('a')
        Sequence::CTRL_A
      when ctrl('b')
        Sequence::CTRL_B
      when ctrl('c')
        Sequence::CTRL_C
      when ctrl('d')
        Sequence::CTRL_D
      when ctrl('e')
        Sequence::CTRL_E
      when ctrl('f')
        Sequence::CTRL_F
      when ctrl('k')
        Sequence::CTRL_K
      when ctrl('l')
        Sequence::CTRL_L
      when ctrl('n')
        Sequence::CTRL_N
      when ctrl('p')
        Sequence::CTRL_P
      when ctrl('r')
        Sequence::CTRL_R
      when ctrl('u')
        Sequence::CTRL_U
      when ctrl('v')
        Sequence::CTRL_V
      when ctrl('x')
        Sequence::CTRL_X
      when '\0'.ord
        Sequence::EOF
      when 0x7f
        Sequence::BACKSPACE
      else
        if chars.size == 1
          chars[0].chr
        end
      end || String.new(chars)
    end

    private def raw(io : T, &) forall T
      {% if T.has_method?(:raw) %}
        if io.tty?
          io.raw { yield io }
        else
          yield io
        end
      {% else %}
        yield io
      {% end %}
    end

    private def ctrl(k)
      (k.ord & 0x1f)
    end
  end
end
