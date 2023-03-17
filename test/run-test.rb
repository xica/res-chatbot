base_dir = File.expand_path(File.join(File.dirname(__FILE__), ".."))
test_dir = File.join(base_dir, "test")

$LOAD_PATH.unshift(base_dir)

require "test/unit"
require_relative "helper"

exit Test::Unit::AutoRunner.run(true, test_dir)
