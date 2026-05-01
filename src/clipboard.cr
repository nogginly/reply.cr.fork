module Reply::Clipboard
  {% if flag?(:linux) %}
    COPY_COMMAND  = ["xclip", "-selection", "clipboard"]
    PASTE_COMMAND = ["xclip", "-selection", "clipboard", "-o"]
    ERROR_MESSAGE = "Install xclip on your system to copy-past expression"
  {% elsif flag?(:darwin) %}
    COPY_COMMAND  = ["pbcopy"]
    PASTE_COMMAND = ["pbpaste"]
    ERROR_MESSAGE = nil
  {% elsif flag?(:win32) %}
    COPY_COMMAND  = ["clip"]
    PASTE_COMMAND = ["powershell", "-command", "Get-Clipboard"]
    ERROR_MESSAGE = nil
  {% end %}

  def self.copy(text : String)
    return if text.empty?
    process = Process.new(COPY_COMMAND[0], COPY_COMMAND[1..], input: Process::Redirect::Pipe)
    process.input.puts(text)
    process.input.close
    process.wait
  rescue e
    puts (ERROR_MESSAGE || e.to_s).colorize.yellow
  end

  def self.paste : String
    output = IO::Memory.new
    process = Process.new(PASTE_COMMAND[0], PASTE_COMMAND[1..], output: output)
    process.wait
    output.to_s.strip
  rescue e
    puts (ERROR_MESSAGE || e.to_s).colorize.yellow
    ""
  end
end
