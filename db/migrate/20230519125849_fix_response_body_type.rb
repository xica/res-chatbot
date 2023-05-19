class FixResponseBodyType < ActiveRecord::Migration[7.0]
  def up
    Response.transaction do
      Response.find_each do |res|
        case res.body
        when String
          res.update!(body: JSON.parse(res.body))
        end
      end
    end
  end

  def down
    # DO NOTHING
  end
end
