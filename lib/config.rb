require 'yaml'

# Loads local configuration from config.yml (gitignored, personal), falling
# back to config.example.yml so the tools still run before setup. Values can
# be overridden by environment variables.
module Config
  PATH = File.expand_path('../config.yml', __dir__)
  EXAMPLE = File.expand_path('../config.example.yml', __dir__)

  module_function

  def data
    @data ||= YAML.safe_load_file(File.exist?(PATH) ? PATH : EXAMPLE) || {}
  end

  # Directory of workout files. WORKOUT_DIR env var wins, then config.
  def workout_dir
    dir = ENV['WORKOUT_DIR'] || data['workout_dir']
    dir && File.expand_path(dir)
  end

  # Functional threshold / critical power in watts; anchors interval detection.
  def ftp
    (ENV['FTP'] || data['ftp'] || 250).to_i
  end

  # Aborts with a setup hint if the workout directory isn't usable.
  def require_workout_dir!
    dir = workout_dir
    return dir if dir && Dir.exist?(dir)

    abort "Set 'workout_dir' in config.yml (copy config.example.yml). " \
          "Currently: #{dir.inspect}"
  end
end
