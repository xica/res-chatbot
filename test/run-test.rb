base_dir = File.expand_path(File.join(File.dirname(__FILE__), ".."))
config_dir = File.join(base_dir, "config")
lib_dir = File.join(base_dir, "lib")
test_dir = File.join(base_dir, "test")

$LOAD_PATH.unshift(config_dir)
$LOAD_PATH.unshift(lib_dir)

require "test/unit"
require_relative "helper"

exit Test::Unit::AutoRunner.run(true, test_dir)
