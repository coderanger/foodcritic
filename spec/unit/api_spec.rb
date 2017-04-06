require "spec_helper"

describe FoodCritic::Api do

  def parse_ast(str)
    api.send(:build_xml, Ripper::SexpBuilder.new(str).parse)
  end

  let(:api) { Object.new.extend(FoodCritic::Api) }

  describe :exposed_api do
    let(:ignorable_methods) do
      api.class.ancestors.map { |a| a.public_methods }.flatten.sort.uniq
    end
    it "exposes the expected api to rule authors" do
      expect(api.public_methods.sort - ignorable_methods).to eq [
        :attribute_access,
        :checks_for_chef_solo?,
        :chef_dsl_methods,
        :chef_node_methods,
        :chef_solo_search_supported?,
        :cookbook_base_path,
        :cookbook_maintainer,
        :cookbook_maintainer_email,
        :cookbook_name,
        :declared_dependencies,
        :field,
        :field_value,
        :file_match,
        :find_resources,
        :gem_version,
        :included_recipes,
        :literal_searches,
        :match,
        :metadata_field,
        :notifications,
        :read_ast,
        :resource_action?,
        :resource_attribute,
        :resource_attribute?,
        :resource_attributes,
        :resource_attributes_by_type,
        :resource_name,
        :resource_type,
        :resources_by_type,
        :ruby_code?,
        :searches,
        :standard_cookbook_subdirs,
        :supported_platforms,
        :template_file,
        :template_paths,
        :templates_included,
        :valid_query?,
      ]
    end
  end

  describe "#attribute_access" do
    let(:ast) { double() }
    it "returns empty if the provided ast does not support XPath" do
      expect(api.attribute_access(nil, :type => :vivified)).to be_empty
    end
    it "returns empty if the provided ast has no matches" do
      expect(ast).to receive(:xpath).with(kind_of(String), kind_of(FoodCritic::Api::AttFilter)).and_return([]).exactly(3).times
      [:vivified, :string, :symbol].each do |access_type|
        expect(api.attribute_access(ast, :type => access_type)).to be_empty
      end
    end
    it "raises if the specified node type is not recognised" do
      allow(ast).to receive(:xpath)
      expect { api.attribute_access(ast, :type => :cymbals) }.to raise_error ArgumentError
    end
    it "does not raise if the specified node type is valid" do
      expect(ast).to receive(:xpath).with(/field/, FoodCritic::Api::AttFilter).and_return([])
      expect(ast).to receive(:xpath).with(/symbol/, FoodCritic::Api::AttFilter).and_return([])
      expect(ast).to receive(:xpath).with(/tstring_content/, FoodCritic::Api::AttFilter).and_return([])
      [:vivified, :symbol, :string].each do |access_type|
        api.attribute_access(ast, :type => access_type)
      end
    end
    it "returns vivified attributes access" do
      call = double()
      expect(call).to receive(:xpath).with(/args_add_block/).and_return([])
      expect(call).to receive(:xpath).with(/ident/).and_return(%w{node bar})
      expect(call).to receive(:xpath).with(/@value/).and_return("foo")
      expect(ast).to receive(:xpath).with(kind_of(String), kind_of(FoodCritic::Api::AttFilter)).and_return([call])
      expect(api.attribute_access(ast, :type => :vivified)).to eq [call]
    end
    it "doesn't flag searching for a node by name as symbol access" do
      ast = parse_ast(%q{baz = search(:node, "name:#{node['foo']['bar']}")[0]})
      expect(api.attribute_access(ast, :type => :symbol)).to be_empty
    end
    describe :ignoring_attributes do
      it "doesn't ignore run_state by default for backwards compatibility" do
        ast = parse_ast("node.run_state['bar'] = 'baz'")
        expect(api.attribute_access(ast)).to_not be_empty
      end
      it "allows run_state to be ignored" do
        ast = parse_ast("node.run_state['bar'] = 'baz'")
        expect(api.attribute_access(ast, :ignore => ["run_state"])).to be_empty
      end
      it "allows run_state to be ignored (symbols access)" do
        ast = parse_ast("node.run_state[:bar] = 'baz'")
        expect(api.attribute_access(ast, :ignore => ["run_state"])).to be_empty
      end
      it "allows any attribute to be ignored" do
        ast = parse_ast("node['bar'] = 'baz'")
        expect(api.attribute_access(ast, :ignore => ["bar"])).to be_empty
      end
      it "allows any attribute to be ignored (symbols access)" do
        ast = parse_ast("node[:bar] = 'baz'")
        expect(api.attribute_access(ast, :ignore => ["bar"])).to be_empty
      end
      it "allows any attribute to be ignored (dot access)" do
        ast = parse_ast("node.bar = 'baz'")
        expect(api.attribute_access(ast, :ignore => ["bar"])).to be_empty
      end
      it "includes the children of attributes" do
        ast = parse_ast("node['foo']['bar'] = 'baz'")
        expect(api.attribute_access(ast).map { |a| a["value"] }).to eq %w{foo bar}
      end
      it "does not include children of removed attributes" do
        ast = parse_ast("node['foo']['bar'] = 'baz'")
        expect(api.attribute_access(ast, :ignore => ["foo"])).to be_empty
      end
      it "coerces ignore values to enumerate them" do
        ast = parse_ast("node.run_state['bar'] = 'baz'")
        expect(api.attribute_access(ast, :ignore => "run_state")).to be_empty
      end
      it "can ignore multiple attributes" do
        ast = parse_ast(%q{
          node['bar'] = 'baz'
          node.foo = 'baz'
        })
        expect(api.attribute_access(ast, :ignore => %w{foo bar})).to be_empty
      end
    end
  end

  describe "#checks_for_chef_solo?" do
    let(:ast) { double() }
    it "raises if the provided ast does not support XPath" do
      expect { api.checks_for_chef_solo?(nil) }.to raise_error ArgumentError
    end
    it "returns false if there is no reference to chef solo" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([]).twice
      expect(api.checks_for_chef_solo?(ast)).to be_falsey
    end
    it "returns true if there is one reference to chef solo" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return(["aref"])
      expect(api.checks_for_chef_solo?(ast)).to be_truthy
    end
    it "returns true if there are multiple references to chef solo" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return(%w{aref aref})
      expect(api.checks_for_chef_solo?(ast)).to be_truthy
    end
  end

  describe "#chef_solo_search_supported?" do
    it "returns false if the recipe path is nil" do
      expect(api.chef_solo_search_supported?(nil)).to be_falsey
    end
    it "returns false if the recipe path does not exist" do
      expect(api.chef_solo_search_supported?("/tmp/non-existent-path")).to be_falsey
    end
  end

  describe "#metadata_field" do
    # TODO we should do this with a double instead
    # but this is the accepted pattern so far so...
    def mock_cookbook(metadata_path)
      dir = File.dirname(metadata_path)
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      File.open(metadata_path, "w") { |file| file.write('name "YOUR_COOKBOOK_NAME"') }
      FileUtils.mkdir_p(File.join(dir, "templates/defaults"))
      File.open(File.join(dir, "templates", "defaults", "test.erb"), "w") { |file| file.write("Some erb") }
    end

    it "returns the 'name' value when passed a metadata file and the name field" do
      mock_cookbook("/tmp/fc/mock/cb/metadata.rb")
      expect(api.metadata_field("/tmp/fc/mock/cb/", "name")).to eq "YOUR_COOKBOOK_NAME"
    end

    it "it raises if a invalid field is requested" do
      expect { api.metadata_field("/tmp/fc/mock/cb/", "bogus_field") }.to raise_error RuntimeError
    end

    it "it raises if a invalid file is requested" do
      expect { api.metadata_field("/tmp/some/bogus/cookbook/path", "name") }.to raise_error RuntimeError
    end
  end

  describe "#cookbook_base_path" do
    # TODO we should do this with a mock instead
    # but this is the accepted pattern so far so...
    def mock_cookbook(metadata_path)
      dir = File.dirname(metadata_path)
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      File.open(metadata_path, "w") { |file| file.write('name "YOUR_COOKBOOK_NAME"') }
      FileUtils.mkdir_p(File.join(dir, "templates/defaults"))
      File.open(File.join(dir, "templates", "defaults", "test.erb"), "w") { |file| file.write("Some erb") }
    end

    it "returns the cookbook dir when passed the path itself" do
      mock_cookbook("/tmp/fc/mock/cb/metadata.rb")
      expect(api.cookbook_base_path("/tmp/fc/mock/cb/")).to eq "/tmp/fc/mock/cb"
    end

    it "returns the cookbook dir when passed a nested directory" do
      mock_cookbook("/tmp/fc/mock/cb/metadata.rb")
      expect(api.cookbook_base_path("/tmp/fc/mock/cb/templates/defaults/test.erb")).to eq "/tmp/fc/mock/cb"
    end

    it "returns the cookbook dir when path contains cookbook like names" do
      mock_cookbook("/tmp/fc/mock/resources/cb/metadata.rb")
      expect(api.cookbook_base_path("/tmp/fc/mock/resources/cb/templates/defaults/test.erb")).to eq "/tmp/fc/mock/resources/cb"
    end

    it "returns the cookbook dir when path has a metadata.json not metadata.rb" do
      mock_cookbook("/tmp/fc/mock/cb/metadata.json")
      expect(api.cookbook_base_path("/tmp/fc/mock/cb/templates/defaults/test.erb")).to eq "/tmp/fc/mock/cb"
    end
  end

  describe "#cookbook_name" do
    def mock_cookbook_metadata(f)
      dir = File.dirname(f)
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      File.open(f, "w") { |file| file.write('name "YOUR_COOKBOOK_NAME"') }
    end

    it "raises if passed a nil" do
      expect { api.cookbook_name(nil) }.to raise_error ArgumentError
    end
    it "raises if passed an empty string" do
      expect { api.cookbook_name("") }.to raise_error ArgumentError
    end
    it "returns the cookbook name when passed a recipe" do
      recipe_path = "cookbooks/apache2/recipes/default.rb"
      expect(api.cookbook_name(recipe_path)).to eq "apache2"
    end
    it "returns the cookbook name when passed the cookbook metadata" do
      expect(api.cookbook_name("cookbooks/apache2/metadata.rb")).to eq "apache2"
    end
    it "returns the cookbook name when passed a template" do
      erb_path = "cookbooks/apache2/templates/default/a2ensite.erb"
      expect(api.cookbook_name(erb_path)).to eq "apache2"
    end
    it "returns the cookbook name when passed the cookbook metadata with a name field" do
      metadata_path = "/tmp/fc/mock/cb/metadata.rb"
      mock_cookbook_metadata(metadata_path)
      expect(api.cookbook_name(metadata_path)).to eq "YOUR_COOKBOOK_NAME"
    end
  end

  describe "#cookbook_maintainer" do
    def mock_cookbook_metadata(f)
      dir = File.dirname(f)
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      File.open(f, "w") { |file| file.write('maintainer "YOUR_COMPANY_NAME"') }
    end
    let(:metadata_path) { "/tmp/fc/mock/cb/metadata.rb" }

    it "raises if passed a nil" do
      expect { api.cookbook_maintainer(nil) }.to raise_error ArgumentError
    end
    it "raises if passed an empty string" do
      expect { api.cookbook_maintainer("") }.to raise_error ArgumentError
    end
    it "raises if the path does not exist" do
      expect { api.cookbook_maintainer("/tmp/non-existent-path") }.to raise_error RuntimeError
    end
    it "returns the cookbook maintainer when passed the cookbook metadata" do
      mock_cookbook_metadata(metadata_path)
      expect(api.cookbook_maintainer(metadata_path)).to eq "YOUR_COMPANY_NAME"
    end
    it "returns the cookbook maintainer when passed a recipe" do
      mock_cookbook_metadata(metadata_path)
      expect(api.cookbook_maintainer("/tmp/fc/mock/cb/recipes/default.rb")).to eq "YOUR_COMPANY_NAME"
    end
    it "returns the cookbook maintainer when passed a template" do
      mock_cookbook_metadata(metadata_path)
      expect(api.cookbook_maintainer("/tmp/fc/mock/cb/templates/default/mock.erb")).to eq "YOUR_COMPANY_NAME"
    end
  end

  describe "#cookbook_maintainer_email" do
    def mock_cookbook_metadata(f)
      dir = File.dirname(f)
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      File.open(f, "w") { |file| file.write('maintainer_email "YOUR_EMAIL"') }
    end
    let(:metadata_path) { "/tmp/fc/mock/cb/metadata.rb" }

    it "raises if passed a nil" do
      expect { api.cookbook_maintainer_email(nil) }.to raise_error ArgumentError
    end
    it "raises if passed an empty string" do
      expect { api.cookbook_maintainer_email("") }.to raise_error ArgumentError
    end
    it "raises if the path does not exist" do
      expect { api.cookbook_maintainer_email("/tmp/non-existent-path") }.to raise_error RuntimeError
    end
    it "returns the cookbook maintainer_email when passed the cookbook metadata" do
      mock_cookbook_metadata(metadata_path)
      expect(api.cookbook_maintainer_email(metadata_path)).to eq "YOUR_EMAIL"
    end
    it "returns the cookbook maintainer_email when passed a recipe" do
      mock_cookbook_metadata(metadata_path)
      expect(api.cookbook_maintainer_email("/tmp/fc/mock/cb/recipes/default.rb")).to eq "YOUR_EMAIL"
    end
    it "returns the cookbook maintainer_email when passed a template" do
      mock_cookbook_metadata(metadata_path)
      expect(api.cookbook_maintainer_email("/tmp/fc/mock/cb/templates/default/mock.erb")).to eq "YOUR_EMAIL"
    end
  end

  describe "#declared_dependencies" do
    it "raises if the ast does not support XPath" do
      expect { api.declared_dependencies(nil) }.to raise_error ArgumentError
    end
    it "returns an empty if there are no declared dependencies" do
      ast = double
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([]).twice
      expect(api.declared_dependencies(ast)).to be_empty
    end
    it "includes only cookbook names in the returned array" do
      ast = Nokogiri::XML(%q{
            <command>
              <ident value="depends">
                <pos line="14" column="0"/>
              </ident>
              <args_add_block value="false">
                <args_add>
                  <args_add>
                    <args_new/>
                    <string_literal>
                      <string_add>
                        <string_content/>
                        <tstring_content value="mysql">
                          <pos line="14" column="9"/>
                        </tstring_content>
                      </string_add>
                    </string_literal>
                  </args_add>
                  <string_literal>
                    <string_add>
                      <string_content/>
                      <tstring_content value="&gt;= 1.2.0">
                        <pos line="14" column="18"/>
                      </tstring_content>
                    </string_add>
                  </string_literal>
                </args_add>
              </args_add_block>
            </command>
      })
      expect(api.declared_dependencies(ast)).to eq ["mysql"]
    end
  end

  describe "#field" do
    describe :simple_ast do
      let(:ast) { parse_ast('name "webserver"') }
      it "raises if the field name is nil" do
        expect { api.field(ast, nil) }.to raise_error ArgumentError
      end
      it "raises if the field name is empty" do
        expect { api.field(ast, "") }.to raise_error ArgumentError
      end
      it "returns empty if the field is not present" do
        expect(api.field(ast, :common_name)).to be_empty
      end
      it "accepts a string for the field name" do
        expect(api.field(ast, "name")).to_not be_empty
      end
      it "accepts a symbol for the field name" do
        expect(api.field(ast, :name)).to_not be_empty
      end
    end
    it "returns fields when the value is an embedded string expression" do
      ast = parse_ast(%q{
        name "#{foo}_#{bar}"
      }.strip)
      expect(api.field(ast, :name).size).to eq 1
    end
    it "returns fields when the value is a method call" do
      ast = parse_ast(%q{
        name generate_name
      }.strip)
      expect(api.field(ast, :name).size).to eq 1
    end
    it "returns both fields if the field is specified twice" do
      ast = parse_ast(%q{
        name "webserver"
        name "database"
      }.strip)
      expect(api.field(ast, :name).size).to eq 2
    end
  end

  describe "#field_value" do
    describe :simple_ast do
      let(:ast) { parse_ast('name "webserver"') }
      it "raises if the field name is nil" do
        expect { api.field_value(ast, nil) }.to raise_error ArgumentError
      end
      it "raises if the field name is empty" do
        expect { api.field_value(ast, "") }.to raise_error ArgumentError
      end
      it "is falsy if the field is not present" do
        expect(api.field_value(ast, :common_name)).to be_falsey
      end
      it "accepts a string for the field name" do
        expect(api.field_value(ast, "name")).to eq "webserver"
      end
      it "accepts a symbol for the field name" do
        expect(api.field_value(ast, :name)).to eq "webserver"
      end
    end
    it "is falsy when the value is an embedded string expression" do
      ast = parse_ast(%q{
        name "#{foo}_#{bar}"
      }.strip)
      expect(api.field_value(ast, :name)).to be_falsey
    end
    it "is falsy when the value is a method call" do
      ast = parse_ast(%q{
        name generate_name('foo')
      }.strip)
      expect(api.field_value(ast, :name)).to be_falsey
    end
    it "returns the last value if the field is specified twice" do
      ast = parse_ast(%q{
        name "webserver"
        name "database"
      }.strip)
      expect(api.field_value(ast, :name)).to eq "database"
    end
  end

  describe "#file_match" do
    it "includes the provided filename in the match" do
      expect(api.file_match("foo.rb")[:filename]).to eq "foo.rb"
    end
    it "retains the full provided filename path in the match" do
      expect(api.file_match("foo/bar/foo.rb")[:filename]).to eq "foo/bar/foo.rb"
    end
    it "raises an error if the provided filename is nil" do
      expect { api.file_match(nil) }.to raise_error ArgumentError
    end
    it "sets the line and column to the beginning of the file" do
      match = api.file_match("bar.rb")
      expect(match[:line]).to eq 1
      expect(match[:column]).to eq 1
    end
  end

  describe "#find_resources" do
    let(:ast) { double() }
    it "returns empty unless the ast supports XPath" do
      expect(api.find_resources(nil)).to be_empty
    end
    it "restricts by resource type when provided" do
      expect(ast).to receive(:xpath).with("//method_add_block[command/ident[@value='file']][command/ident/@value != 'action']").and_return(["method_add_block"])
      api.find_resources(ast, :type => "file")
    end
    it "does not restrict by resource type when not provided" do
      expect(ast).to receive(:xpath).with("//method_add_block[command/ident][command/ident/@value != 'action']").and_return(["method_add_block"])
      api.find_resources(ast)
    end
    it "allows resource type to be specified as :any" do
      expect(ast).to receive(:xpath).with("//method_add_block[command/ident][command/ident/@value != 'action']").and_return(["method_add_block"])
      api.find_resources(ast, :type => :any)
    end
    it "returns any matches" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return(["method_add_block"])
      expect(api.find_resources(ast)).to eq ["method_add_block"]
    end
  end

  describe "#included_recipes" do
    let(:ast) { double() }
    it "raises if the ast does not support XPath" do
      expect { api.included_recipes(nil) }.to raise_error ArgumentError
    end
    it "returns an empty hash if there are no included recipes" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([])
      expect(api.included_recipes(ast).keys).to be_empty
    end
    it "returns a hash keyed by recipe name" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([{ "value" => "foo::bar" }])
      expect(api.included_recipes(ast).keys).to eq ["foo::bar"]
    end
    it "returns a hash where the values are the matching nodes" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([{ "value" => "foo::bar" }])
      expect(api.included_recipes(ast).values).to eq [[{ "value" => "foo::bar" }]]
    end
    it "correctly keys an included recipe specified as a string literal" do
      ast = parse_ast(%q{
        include_recipe "foo::default"
      })
      expect(api.included_recipes(ast).keys).to eq ["foo::default"]
    end
    describe "embedded expression - recipe name" do
      let(:ast) do
        parse_ast(%q{
          include_recipe "foo::#{bar}"
        })
      end
      it "returns the literal string component by default" do
        expect(api.included_recipes(ast).keys).to eq ["foo::"]
      end
      it "returns the literal string part of the AST" do
        expect(api.included_recipes(ast)["foo::"].first).to respond_to :xpath
      end
      it "returns empty if asked to exclude statements with embedded expressions" do
        expect(api.included_recipes(ast, :with_partial_names => false)).to be_empty
      end
      it "returns the literals if asked to include statements with embedded expressions" do
        expect(api.included_recipes(ast, :with_partial_names => true).keys).to eq ["foo::"]
      end
    end
    describe "embedded expression - cookbook name" do
      let(:ast) do
        parse_ast(%q{
          include_recipe "#{foo}::bar"
        })
      end
      it "returns the literal string component by default" do
        expect(api.included_recipes(ast).keys).to eq ["::bar"]
      end
      it "returns the literal string part of the AST" do
        expect(api.included_recipes(ast)["::bar"].first).to respond_to :xpath
      end
      it "returns empty if asked to exclude statements with embedded expressions" do
        expect(api.included_recipes(ast, :with_partial_names => false)).to be_empty
      end
    end
    describe "embedded expression - partial cookbook name" do
      let(:ast) do
        parse_ast(%q{
          include_recipe "#{foo}_foo::bar"
        })
      end
      it "returns the literal string component by default" do
        expect(api.included_recipes(ast).keys).to eq ["_foo::bar"]
      end
      it "returns the literal string part of the AST" do
        expect(api.included_recipes(ast)["_foo::bar"].first).to respond_to :xpath
      end
      it "returns empty if asked to exclude statements with embedded expressions" do
        expect(api.included_recipes(ast, :with_partial_names => false)).to be_empty
      end
    end
  end

  describe :AttFilter do
    describe "#is_att_type" do
      let(:filter) { FoodCritic::Api::AttFilter.new }
      it "returns empty if the argument is not enumerable" do
        expect(filter.is_att_type(nil)).to be_empty
      end
      it "filters out values that are not Chef node attribute types" do
        nodes = %w{node node badger default override ostrich set normal}
        expect(filter.is_att_type(nodes).uniq.size).to eq 5
      end
      it "returns all filtered nodes" do
        nodes = %w{node node override default normal set set override}
        expect(filter.is_att_type(nodes)).to eq nodes
      end
      it "returns empty if there are no Chef node attribute types" do
        nodes = %w{squirrel badger pooh tigger}
        expect(filter.is_att_type(nodes)).to be_empty
      end
    end
  end

  describe "#literal_searches" do
    let(:ast) { double() }
    it "returns empty if the AST does not support XPath expressions" do
      expect(api.literal_searches(nil)).to be_empty
    end
    it "returns empty if the AST has no elements" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([])
      expect(api.literal_searches(ast)).to be_empty
    end
    it "returns the AST elements for each literal search" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return(["tstring_content"])
      expect(api.literal_searches(ast)).to eq ["tstring_content"]
    end
  end

  describe "#match" do
    it "raises if the provided node is nil" do
      expect { api.match(nil) }.to raise_error ArgumentError
    end
    it "raises if the provided node does not support XPath" do
      expect { api.match(Object.new) }.to raise_error ArgumentError
    end
    it "returns nil if there is no nested position node" do
      node = double()
      expect(node).to receive(:xpath).with("descendant::pos").and_return([])
      expect(api.match(node)).to be nil
    end
    it "uses the position of the first position node if there are multiple" do
      node = double()
      expect(node).to receive(:xpath).with("descendant::pos").and_return([
        { "name" => "pos", "line" => "1", "column" => "10" },
        { "name" => "pos", "line" => "3", "column" => "16" }])
      match = api.match(node)
      expect(match[:line]).to eq 1
      expect(match[:column]).to eq 10
    end
    describe :matched_node_name do
      let(:node) do
        node = double()
        expect(node).to receive(:xpath).with("descendant::pos").and_return([{ "name" => "pos", "line" => "1", "column" => "10" }])
        node
      end
      it "includes the name of the node in the match" do
        expect(node).to receive(:name).and_return("command")
        expect(api.match(node)).to eq({ :matched => "command", :line => 1,
                                        :column => 10 })
      end
      it "sets the matched name to empty if the element does not have a name" do
        expect(api.match(node)).to eq({ :matched => "", :line => 1, :column => 10 })
      end
    end
  end

  describe "#notifications" do
    it "returns empty if the provided AST does not support XPath" do
      expect(api.notifications(nil)).to be_empty
    end
    it "returns empty if there are no notifications" do
      ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
          end
      })
      expect(api.notifications(ast)).to be_empty
    end
    describe "malformed syntax" do
      it "returns empty if no notifies value is provided" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            notifies
          end
        })
        expect(api.notifications(ast)).to be_empty
      end
      it "returns empty if no subscribes value is provided" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            subscribes
          end
        })
        expect(api.notifications(ast)).to be_empty
      end
      it "returns empty if only the notifies action is provided" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            notifies :restart
          end
        })
        expect(api.notifications(ast)).to be_empty
      end
      it "returns empty if only the subscribes action is provided" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            subscribes :restart
          end
        })
        expect(api.notifications(ast)).to be_empty
      end
      describe "returns empty if the service name is missing" do
        it "old-style notifications" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              notifies :restart, resources(:service)
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "old-style subscriptions" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              subscribes:restart, resources(:service)
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "new-style notifications" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              notifies :restart, "service"
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "new-style subscriptions" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              subscribes:restart, "service"
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
      end
      describe "returns empty if the resource type is missing" do
        it "old-style notifications" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              notifies :restart, resources("nscd")
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "old-style subscriptions" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              subscribes :restart, resources("nscd")
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "new-style notifications" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              notifies :restart, "nscd"
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "new-style subscriptions" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              subscribes :restart, "nscd"
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
      end
      describe "returns empty if the resource name is missing" do
        it "old-style notifications" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              notifies :restart, resources(:service)
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "old-style subscriptions" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              subscribes :restart, resources(:service)
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "new-style notifications" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              notifies :restart, "service[]"
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
        it "new-style subscriptions" do
          ast = parse_ast(%q{
            template "/etc/nscd.conf" do
              source "nscd.conf"
              owner "root"
              group "root"
              subscribes :restart, "service[]"
            end
          })
          expect(api.notifications(ast)).to be_empty
        end
      end
      it "returns empty if the left square bracket is missing" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            subscribes :restart, "servicefoo]"
          end
        })
        expect(api.notifications(ast)).to be_empty
      end
      it "returns empty if the right square bracket is missing" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            subscribes :restart, "service[foo"
          end
        })
        expect(api.notifications(ast)).to be_empty
      end
    end
    it "understands the old-style notifications" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies :restart, resources(:service => "nscd")
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :old,
        }]
    end
    it "understands old-style notifications with :'symbol' literals as action" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies :'soft-restart', resources(:service => "nscd")
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :'soft-restart',
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :old,
        }]
    end
    it "understands old-style notifications with added parentheses" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies(:restart, resources(:service => "nscd"))
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :old,
        }]
    end
    it "understands old-style notifications with ruby 1.9 hash syntax" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies :restart, resources(service: "nscd")
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :old,
        }]
    end
    it "understands the old-style subscriptions" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          subscribes :restart, resources(:service => "nscd")
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :subscribes,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :old,
        }]
    end
    it "understands old-style subscriptions with added parentheses" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          subscribes(:restart, resources(:service => "nscd"))
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :subscribes,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :old,
        }]
    end
    it "understands the new-style notifications" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies :restart, "service[nscd]"
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :new,
        }]
    end
    it "understands new-style notifications with :'symbol' literals as action" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies :'soft-restart', "service[nscd]"
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :'soft-restart',
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :new,
        }]
    end
    it "understands new-style notifications with added parentheses" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies(:restart, "service[nscd]")
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :new,
        }]
    end
    it "understands the new-style subscriptions" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          subscribes :restart, "service[nscd]"
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :subscribes,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :new,
        }]
    end
    it "understands new-style subscriptions with added parentheses" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          subscribes(:restart, "service[nscd]")
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :subscribes,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :delayed,
          :style => :new,
        }]
    end
    describe "supports a resource both notifying and subscribing" do
      it "old-style notifications" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            notifies :restart, resources(:service => "nscd")
            subscribes :create, resources(:template => "/etc/nscd.conf")
          end
        })
        expect(api.notifications(ast)).to eq [
          {
            :type => :notifies,
            :action => :restart,
            :resource_type => :service,
            :resource_name => "nscd",
            :timing => :delayed,
            :style => :old,
          },
          {
            :type => :subscribes,
            :action => :create,
            :resource_type => :template,
            :resource_name => "/etc/nscd.conf",
            :timing => :delayed,
            :style => :old,
          },
        ]
      end
      it "new-style notifications" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            notifies :restart, "service[nscd]"
            subscribes :create, "template[/etc/nscd.conf]"
          end
        })
        expect(api.notifications(ast)).to eq [
          {
            :type => :notifies,
            :action => :restart,
            :resource_type => :service,
            :resource_name => "nscd",
            :timing => :delayed,
            :style => :new,
          },
          {
            :type => :subscribes,
            :action => :create,
            :resource_type => :template,
            :resource_name => "/etc/nscd.conf",
            :timing => :delayed,
            :style => :new,
          },
        ]
      end
    end
    it "understands the old-style notifications with timing" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies :restart, resources(:service => "nscd"), :immediately
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :immediate,
          :style => :old,
        }]
    end
    it "understands the old-style subscriptions with timing" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          subscribes :restart, resources(:service => "nscd"), :immediately
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :subscribes,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :immediate,
          :style => :old,
        }]
    end
    it "understands the new-style notifications with timing" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          notifies :restart, "service[nscd]", :immediately
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :notifies,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :immediate,
          :style => :new,
        }]
    end
    it "understands the new-style subscriptions with timing" do
      ast = parse_ast(%q{
        template "/etc/nscd.conf" do
          source "nscd.conf"
          owner "root"
          group "root"
          subscribes :restart, "service[nscd]", :immediately
        end
      })
      expect(api.notifications(ast)).to eq [{
          :type => :subscribes,
          :action => :restart,
          :resource_type => :service,
          :resource_name => "nscd",
          :timing => :immediate,
          :style => :new,
        }]
    end
    describe "can be passed an individual resource" do
      it "old-style notifications" do
        ast = parse_ast(%q{
          service "nscd" do
            action :start
          end
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            notifies :restart, resources(:service => "nscd")
          end
        })
        expect(api.notifications(api.find_resources(ast, :type => :template).first)).to eq [
          { :type => :notifies, :action => :restart, :resource_type => :service,
            :resource_name => "nscd", :timing => :delayed,
            :style => :old },
        ]
      end
      it "old-style subscriptions" do
        ast = parse_ast(%q{
          service "nscd" do
            action :start
          end
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            subscribes :restart, resources(:service => "nscd")
          end
        })
        expect(api.notifications(api.find_resources(ast, :type => :template).first)).to eq [
          { :type => :subscribes, :action => :restart, :resource_type => :service,
            :resource_name => "nscd", :timing => :delayed,
            :style => :old },
        ]
      end
      it "new-style notifications" do
        ast = parse_ast(%q{
          service "nscd" do
            action :start
          end
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            notifies :restart, "service[nscd]"
          end
        })
        expect(api.notifications(api.find_resources(ast, :type => :template).first)).to eq [
          { :type => :notifies, :action => :restart, :resource_type => :service,
            :resource_name => "nscd", :timing => :delayed,
            :style => :new },
        ]
      end
      it "new-style subscriptions" do
        ast = parse_ast(%q{
          service "nscd" do
            action :start
          end
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            subscribes :restart, "service[nscd]"
          end
        })
        expect(api.notifications(api.find_resources(ast, :type => :template).first)).to eq [
          { :type => :subscribes, :action => :restart, :resource_type => :service,
            :resource_name => "nscd", :timing => :delayed,
            :style => :new },
        ]
      end
    end
    describe "supports multiple notifications on a single resource" do
      it "old-style notifications" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            notifies :stop, resources(:service => "nscd")
            notifies :start, resources(:service => "nscd")
          end
        })
        expect(api.notifications(ast)).to eq [
            { :type => :notifies, :action => :stop, :resource_type => :service,
              :resource_name => "nscd", :timing => :delayed,
              :style => :old },
            { :type => :notifies, :action => :start, :resource_type => :service,
              :resource_name => "nscd", :timing => :delayed,
              :style => :old },
          ]
      end
      it "old-style subscriptions" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            subscribes :stop, resources(:service => "nscd")
            subscribes :start, resources(:service => "nscd")
          end
        })
        expect(api.notifications(ast)).to eq [
            { :type => :subscribes, :action => :stop, :resource_type => :service,
              :resource_name => "nscd", :timing => :delayed,
              :style => :old },
            { :type => :subscribes, :action => :start, :resource_type => :service,
              :resource_name => "nscd", :timing => :delayed,
              :style => :old },
          ]
      end
      it "new-style notifications" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            notifies :stop, "service[nscd]"
            notifies :start, "service[nscd]"
          end
        })
        expect(api.notifications(ast)).to eq [
            { :type => :notifies, :action => :stop, :resource_type => :service,
              :resource_name => "nscd", :timing => :delayed,
              :style => :new },
            { :type => :notifies, :action => :start, :resource_type => :service,
              :resource_name => "nscd", :timing => :delayed,
              :style => :new },
          ]
      end
      it "new-style subscriptions" do
        ast = parse_ast(%q{
          template "/etc/nscd.conf" do
            source "nscd.conf"
            owner "root"
            group "root"
            subscribes :stop, "service[nscd]"
            subscribes :start, "service[nscd]"
          end
        })
        expect(api.notifications(ast)).to eq [
            { :type => :subscribes, :action => :stop, :resource_type => :service,
              :resource_name => "nscd", :timing => :delayed,
              :style => :new },
            { :type => :subscribes, :action => :start, :resource_type => :service,
              :resource_name => "nscd", :timing => :delayed,
              :style => :new },
          ]
      end
    end
    describe "understands notifications for an execute resource" do
      it "old-style notifications" do
        ast = parse_ast(%q{
          template "/tmp/foo.bar" do
            source "foo.bar.erb"
            notifies :run, resources(:execute => "foo")
          end
        })
        expect(api.notifications(ast)).to eq [
           { :type => :notifies, :action => :run, :resource_type => :execute,
             :resource_name => "foo", :timing => :delayed,
             :style => :old }
          ]
      end
      it "old-style subscriptions" do
        ast = parse_ast(%q{
          template "/tmp/foo.bar" do
            source "foo.bar.erb"
            subscribes :run, resources(:execute => "foo")
          end
        })
        expect(api.notifications(ast)).to eq [
           { :type => :subscribes, :action => :run, :resource_type => :execute,
             :resource_name => "foo", :timing => :delayed,
             :style => :old }
          ]
      end
      it "old-style notifications" do
        ast = parse_ast(%q{
          template "/tmp/foo.bar" do
            source "foo.bar.erb"
            notifies :run, "execute[foo]"
          end
        })
        expect(api.notifications(ast)).to eq [
           { :type => :notifies, :action => :run, :resource_type => :execute,
             :resource_name => "foo", :timing => :delayed,
             :style => :new }
          ]
      end
      it "old-style subscriptions" do
        ast = parse_ast(%q{
          template "/tmp/foo.bar" do
            source "foo.bar.erb"
            subscribes :run, "execute[foo]"
          end
        })
        expect(api.notifications(ast)).to eq [
           { :type => :subscribes, :action => :run, :resource_type => :execute,
             :resource_name => "foo", :timing => :delayed,
             :style => :new }
          ]
      end
    end
    describe "sets the notification timing to delayed if specified" do
      it "old-style notifications" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            notifies :run, resources(execute => "robespierre"), :delayed
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :delayed
      end
      it "old-style subscriptions" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            subscribes :run, resources(execute => "robespierre"), :delayed
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :delayed
      end
      it "new-style notifications" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            notifies :run, "execute[robespierre]", :delayed
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :delayed
      end
      it "new-style subscriptions" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            subscribes :run, "execute[robespierre]", :delayed
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :delayed
      end
    end
    describe "sets the notification timing to immediate if specified as immediate" do
      it "old-style notifications" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            notifies :run, resources(execute => "robespierre"), :immediate
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :immediate
      end
      it "old-style subscriptions" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            subscribes :run, resources(execute => "robespierre"), :immediate
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :immediate
      end
      it "new-style notifications" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            notifies :run, "execute[robespierre]", :immediate
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :immediate
      end
      it "new-style subscriptions" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            subscribes :run, "execute[robespierre]", :immediate
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :immediate
      end
    end

    describe "sets the notification timing to immediate if specified as immediately" do
      it "old-style notifications" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            notifies :run, resources(execute => "robespierre"), :immediately
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :immediate
      end
      it "old-style subscriptions" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            subscribes :run, resources(execute => "robespierre"), :immediately
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :immediate
      end
      it "new-style notifications" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            notifies :run, "execute[robespierre]", :immediately
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :immediate
      end
      it "new-style subscriptions" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            subscribes :run, "execute[robespierre]", :immediately
          end
        })
        expect(api.notifications(ast).first[:timing]).to eq :immediate
      end
    end
    it "passes unrecognised notification timings through unchanged" do
      ast = parse_ast(%q{
        template "/etc/foo.conf" do
          notifies :run, resources(execute => "robespierre"), :forthwith
        end
      })
      expect(api.notifications(ast).first[:timing]).to eq :forthwith
    end
    describe "resource names as expressions" do
      describe "returns the AST for an embedded string" do
        it "old-style notifications" do
          ast = parse_ast(%q{
            template "/etc/foo.conf" do
              notifies :create, resources(:template => "/etc/bar/#{resource}.bar")
            end
          })
          expect(api.notifications(ast).first[:resource_name]).to respond_to :xpath
        end
        it "new-style notifications" do
          ast = parse_ast(%q{
            template "/etc/foo.conf" do
              notifies :create, "template[/etc/bar/#{resource}.bar]"
            end
          })
          expect(api.notifications(ast).first[:resource_name]).to respond_to :xpath
        end
        it "new-style notifications - complete resource_name" do
          ast = parse_ast(%q{
            template "/etc/foo.conf" do
              notifies :create, "template[#{template_path}]"
            end
          })
          expect(api.notifications(ast).first[:resource_name]).to respond_to :xpath
        end
      end
      describe "returns the AST for node attribute" do
        it "old-style notifications" do
          ast = parse_ast(%q{
            template "/etc/foo.conf" do
              notifies :restart, resources(:service => node['foo']['service'])
            end
          })
          expect(api.notifications(ast).first[:resource_name]).to respond_to :xpath
        end
        it "new-style notifications" do
          ast = parse_ast(%q{
            template "/etc/foo.conf" do
              notifies :restart, "service[#{node['foo']['service']}]"
            end
          })
          expect(api.notifications(ast).first[:resource_name]).to respond_to :xpath
        end
      end
      describe "returns the AST for variable reference" do
        it "old-style notifications" do
          ast = parse_ast(%q{
            template "/etc/foo.conf" do
              notifies :restart, resources(:service => my_service)
            end
          })
          expect(api.notifications(ast).first[:resource_name]).to respond_to :xpath
        end
        it "new-style notifications" do
          ast = parse_ast(%q{
            template "/etc/foo.conf" do
              notifies :restart, "service[#{my_service}]"
            end
          })
          expect(api.notifications(ast).first[:resource_name]).to respond_to :xpath
        end
      end
    end
    describe "mark style of notification" do
      it "specifies that the notification was in the old style" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            notifies :restart, resources(:service => 'foo')
          end
        })
        expect(api.notifications(ast).first[:style]).to eq :old
      end
      it "specifies that the notification was in the new style" do
        ast = parse_ast(%q{
          template "/etc/foo.conf" do
            notifies :restart, "service[foo]"
          end
        })
        expect(api.notifications(ast).first[:style]).to eq :new
      end
    end
  end

  describe "#read_ast" do
    it "raises if the file cannot be read" do
      expect { api.read_ast(nil) }.to raise_error TypeError
    end
  end

  describe "#resource_attribute" do
    let(:resource) do
      Class.new do
        def xpath(str)
          raise "Not expected"
        end
      end.new
    end
    it "raises if the resource does not support XPath" do
      expect { api.resource_attribute(nil, "mode") }.to raise_error ArgumentError
    end
    it "raises if the attribute name is empty" do
      expect { api.resource_attribute(resource, "") }.to raise_error ArgumentError
    end
  end

  describe "#resource_attributes" do
    def str_to_atts(str)
      api.resource_attributes(api.find_resources(parse_ast(str)).first)
    end
    it "raises if the resource does not support XPath" do
      expect { api.resource_attributes(nil) }.to raise_error ArgumentError
    end
    it "returns a string value for a literal string" do
      atts = str_to_atts(%q{
        directory "/foo/bar" do
          owner "root"
        end
      })
      expect(atts["owner"]).to eq "root"
    end
    it "returns a truthy value for a literal true" do
      atts = str_to_atts(%q{
        directory "/foo/bar" do
          recursive true
        end
      })
      expect(atts["recursive"]).to be true
    end
    it "returns a truthy value for a literal false" do
      atts = str_to_atts(%q{
        directory "/foo/bar" do
          recursive false
        end
      })
      expect(atts["recursive"]).to be false
    end
    it "decodes numeric attributes correctly" do
      atts = str_to_atts(%q{
        directory "/foo/bar" do
          owner "root"
          mode 0755
        end
      })
      expect(atts["mode"]).to eq "0755"
    end
    describe "block attributes" do
      it "includes attributes with brace block values in the result" do
        atts = str_to_atts(%q{
          file "/etc/foo" do
            mode "0600"
            action :create
            only_if { File.exists?("/etc/bar") }
          end
        })
        expect(atts["only_if"]).to respond_to :xpath
        expect(atts["only_if"].name).to eq "brace_block"
      end
      it "includes attributes with do block values in the result" do
        atts = str_to_atts(%q{
          file "/etc/foo" do
            mode "0600"
            action :create
            only_if do
              !File.exists?(foo) || (File.exists?(bar) &&
                File.mtime(baz) < last_changedate)
            end
          end
        })
        expect(atts["only_if"]).to respond_to :xpath
        expect(atts["only_if"].name).to eq "do_block"
      end
      it "supports multiple block attributes" do
        atts = str_to_atts(%q{
          file "/etc/foo" do
            mode "0600"
            action :create
            only_if { false }
            not_if { true }
          end
        })
        expect(atts["only_if"]).to respond_to :xpath
        expect(atts["only_if"].name).to eq "brace_block"
        expect(atts["not_if"]).to respond_to :xpath
        expect(atts["not_if"].name).to eq "brace_block"
      end
      it "doesn't include method calls in ruby blocks" do
        atts = str_to_atts(%q{
          ruby_block "example" do
            block do
              foo do |bar|
                Chef::Log.info(bar)
              end
            end
            only_if { true }
            not_if { false }
          end
        })
        expect(atts.keys).to_not include "foo"
        expect(atts["block"]).to respond_to :xpath
        expect(atts["block"].name).to eq "do_block"
        expect(atts["only_if"]).to respond_to :xpath
        expect(atts["only_if"].name).to eq "brace_block"
        expect(atts["not_if"]).to respond_to :xpath
        expect(atts["not_if"].name).to eq "brace_block"
      end
      it "includes notifications in the result" do
        atts = str_to_atts(%q{
          template "/etc/httpd.conf" do
            notifies :restart, "service[apache]"
          end
        })
        expect(atts["notifies"]).to respond_to :xpath
        expect(atts["notifies"].name).to eq "args_add_block"
      end
      it "includes old-style notifications in the result" do
        atts = str_to_atts(%q{
          template "/etc/httpd.conf" do
            notifies :restart, resources(:service => "apache")
          end
        })
        expect(atts["notifies"]).to respond_to :xpath
        expect(atts["notifies"].name).to eq "args_add_block"
      end
    end
  end

  describe "#resource_attributes_by_type" do
    it "raises if the ast does not support XPath" do
      expect { api.resource_attributes_by_type(nil) }.to raise_error ArgumentError
    end
    it "returns an empty hash if there are no resources" do
      ast = double()
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([])
      expect(api.resource_attributes_by_type(ast)).to be_empty
    end
  end

  describe "#resource_name" do
    it "raises if the resource does not support XPath" do
      expect { api.resource_name("foo") }.to raise_error ArgumentError
    end
    it "returns the resource name for a resource" do
      ast = double()
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return("bob")
      expect(api.resource_name(ast)).to eq "bob"
    end
  end

  describe "#resources_by_type" do
    it "raises if the ast does not support XPath" do
      expect { api.resources_by_type(nil) }.to raise_error ArgumentError
    end
    it "returns an empty hash if there are no resources" do
      ast = double()
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([])
      expect(api.resources_by_type(ast)).to be_empty
    end
  end

  describe "#resource_type" do
    it "raises if the resource does not support XPath" do
      expect { api.resource_type(nil) }.to raise_error ArgumentError
    end
    it "raises if the resource type cannot be determined" do
      ast = double()
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return("")
      expect { api.resource_type(ast) }.to raise_error ArgumentError
    end
    it "returns the resource type for a resource" do
      ast = double()
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return("directory")
      expect(api.resource_type(ast)).to eq "directory"
    end
  end

  describe "#ruby_code?" do
    it "says a nil is not ruby code" do
      expect(api.ruby_code?(nil)).to be_falsey
    end
    it "says an empty string is not ruby code" do
      expect(api.ruby_code?("")).to be_falsey
    end
    it "coerces arguments to a string" do
      expect(api.ruby_code?(%w{foo bar})).to be_truthy
    end
    it "returns true for a snippet of ruby code" do
      expect(api.ruby_code?("assert api.ruby_code?(nil)")).to be_truthy
    end
    it "returns false for a unix command" do
      expect(api.ruby_code?("find -type f -print")).to be_falsey
    end
  end

  describe "#searches" do
    let(:ast) { double() }
    it "returns empty if the AST does not support XPath expressions" do
      expect(api.searches("not-an-ast")).to be_empty
    end
    it "returns empty if the AST has no elements" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return([])
      expect(api.searches(ast)).to be_empty
    end
    it "returns the AST elements for each use of search" do
      expect(ast).to receive(:xpath).with(kind_of(String)).and_return(["ident"])
      expect(api.searches(ast)).to eq ["ident"]
    end
  end

  describe "#standard_cookbook_subdirs" do
    it "is enumerable" do
      api.standard_cookbook_subdirs.each { |s| s }
    end
    it "is sorted in alphabetical order" do
      expect(api.standard_cookbook_subdirs).to eq api.standard_cookbook_subdirs.sort
    end
    it "includes the directories generated by knife create cookbook" do
      %w{attributes definitions files libraries providers recipes resources
         templates}.each do |dir|
        expect(api.standard_cookbook_subdirs).to include dir
      end
    end
    it "does not include the spec directory" do
      expect(api.standard_cookbook_subdirs).to_not include "spec"
    end
    it "does not include a subdirectory of a subdirectory" do
      expect(api.standard_cookbook_subdirs).to_not include "default"
    end
  end

  describe "#supported_platforms" do
    def supports(str)
      api.supported_platforms(parse_ast(str))
    end
    it "returns an empty if no platforms are specified as supported" do
      expect(supports("name 'example'")).to be_empty
    end
    describe :ignored_support_declarations do
      it "should ignore supports without any arguments" do
        expect(supports("supports")).to be_empty
      end
      it "should ignore supports where an embedded string expression is used" do
        expect(supports('supports "red#{hat}"')).to be_empty
      end
    end
    it "returns the supported platform names if multiple are given" do
      expect(supports(%q{
        supports "redhat"
        supports "scientific"
      })).to eq [{ :platform => "redhat", :versions => [] },
                 { :platform => "scientific", :versions => [] }]
    end
    it "sorts the platform names in alphabetical order" do
      expect(supports(%q{
        supports "scientific"
        supports "redhat"
      })).to eq [{ :platform => "redhat", :versions => [] },
                 { :platform => "scientific", :versions => [] }]
    end
    it "handles support declarations that include version constraints" do
      expect(supports(%q{
        supports "redhat", '>= 6'
      })).to eq [{ :platform => "redhat", :versions => [">= 6"] }]
    end
    it "handles support declarations that include obsoleted version constraints" do
      expect(supports(%q{
        supports 'redhat', '> 5.0', '< 7.0'
        supports 'scientific', '> 5.0', '< 6.0'
      })).to eq [{ :platform => "redhat", :versions => ["> 5.0", "< 7.0"] },
                 { :platform => "scientific", :versions => ["> 5.0", "< 6.0"] }]
    end
    it "normalises platform symbol references to strings" do
      expect(supports(%q{
        supports :ubuntu
      })).to eq [{ :platform => "ubuntu", :versions => [] }]
    end
    it "handles support declarations as symbols that include version constraints" do
      expect(supports(%q{
        supports :redhat, '>= 6'
      })).to eq [{ :platform => "redhat", :versions => [">= 6"] }]
    end
    it "understands support declarations that use word lists" do
      expect(supports(%q{
        %w{redhat centos fedora}.each do |os|
          supports os
        end
      })).to eq [{ :platform => "centos", :versions => [] },
                 { :platform => "fedora", :versions => [] },
                 { :platform => "redhat", :versions => [] }]
    end
  end

  describe "#templates_included" do

    def all_templates
      [
        "templates/default/main.erb",
        "templates/default/included_1.erb",
        "templates/default/included_2.erb",
      ]
    end

    def template_ast(content)
      parse_ast(FoodCritic::Template::ExpressionExtractor.new.extract(
        content).map { |e| e[:code] }.join(";"))
    end

    it "returns the path of the containing template when there are no partials" do
      ast = parse_ast("<%= foo.erb %>")
      expect(api).to receive(:read_ast).with("foo.erb").and_return(ast)
      expect(api.templates_included(["foo.erb"], "foo.erb")).to eq ["foo.erb"]
    end

    it "returns the path of the containing template and any partials" do
      main_ast = template_ast('<%= render "included_1.erb" %>
                                <%= render "included_2.erb" %>')
      inner_ast = template_ast("<%= @foo %>")
      expect(api).to receive(:read_ast).with(/main/).and_return(main_ast)
      expect(api).to receive(:read_ast).and_return(inner_ast).twice
      expect(api.templates_included(all_templates, "templates/default/main.erb")).to eq [
        "templates/default/main.erb",
        "templates/default/included_1.erb",
        "templates/default/included_2.erb",
      ]
    end

    it "doesn't mistake render options for partial template names" do
      main_ast = template_ast('<%= render "included_1.erb",
                               :variables => {:foo => "included_2.erb"} %>')
      inner_ast = template_ast("<%= @foo %>")
      expect(api).to receive(:read_ast).with(/main/).and_return(main_ast)
      expect(api).to receive(:read_ast).and_return(inner_ast)
      expect(api.templates_included(all_templates, "templates/default/main.erb")).to eq [
        "templates/default/main.erb",
        "templates/default/included_1.erb",
      ]
    end

    it "raises if included partials have cycles" do
      main_ast = template_ast('<%= render "included_1.erb" %>
                                <%= render "included_2.erb" %>')
      loop_ast = template_ast('<%= render "main.erb" %>')
      inner_ast = template_ast("<%= foo %>")
      expect(api).to receive(:read_ast).with(/main/).and_return(main_ast).at_least(:once)
      expect(api).to receive(:read_ast).with(/included_2/).and_return(loop_ast).at_least(:once)
      expect(api).to receive(:read_ast).and_return(inner_ast).at_least(:once)
      expect { api.templates_included(all_templates, "templates/default/main.erb") }.to raise_error(FoodCritic::Api::RecursedTooFarError, "templates/default/main.erb")
    end
  end

end