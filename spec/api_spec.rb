require File.dirname(__FILE__) + '/spec_helper'
require File.dirname(__FILE__) + '/../lib/clickatell'

class FakeHttp
  def start(&block)
    yield self
  end
end

module Clickatell
  
  describe "API Command" do
    before do
      @command = API::Command.new('cmdname')
    end
    
    after do
      Clickatell::API.api_service_host = nil
    end
    
    it "should return encoded URL for the specified command and parameters" do
      url = @command.with_params(:param_one => 'abc', :param_two => '123')
      url.should == URI.parse("http://api.clickatell.com/http/cmdname?param_one=abc&param_two=123")
    end
    
    it "should URL encode any special characters in parameters" do
      url = @command.with_params(:param_one => 'abc', :param_two => 'hello world & goodbye cruel world <grin>')
      url.should == URI.parse("http://api.clickatell.com/http/cmdname?param_one=abc&param_two=hello+world+%26+goodbye+cruel+world+%3Cgrin%3E")
    end
    
    it "should use a custom host when constructing command URLs if specified" do
      Clickatell::API.api_service_host = 'api.clickatell-custom.co.uk'
      url = @command.with_params(:param_one => 'abc', :param_two => '123')
      url.should == URI.parse("http://api.clickatell-custom.co.uk/http/cmdname?param_one=abc&param_two=123")
    end
    
    it "should use the default host if specified custom host is nil" do
      Clickatell::API.api_service_host = nil
      url = @command.with_params(:param_one => 'abc', :param_two => '123')
      url.should == URI.parse("http://api.clickatell.com/http/cmdname?param_one=abc&param_two=123")
    end
    
    it "should use the default host if specified custom host is an empty string" do
      Clickatell::API.api_service_host = ''
      url = @command.with_params(:param_one => 'abc', :param_two => '123')
      url.should == URI.parse("http://api.clickatell.com/http/cmdname?param_one=abc&param_two=123")
    end
  end
  
  describe "Secure API Command" do
    before do
      @command = API::Command.new('cmdname', 'http', :secure => true)
    end
    
    it "should use HTTPS" do
      url = @command.with_params(:param_one => 'abc', :param_two => '123')
      url.should == URI.parse("https://api.clickatell.com/http/cmdname?param_one=abc&param_two=123")
    end
  end
    
  describe "Command executor" do
    it "should create an API command with the given params" do
      executor = API::CommandExecutor.new(:session_id => '12345')
      executor.stubs(:get_response).returns([])
      API::Command.expects(:new).with('cmdname', 'http', :secure => false).returns(command = stub('Command'))
      command.expects(:with_params).with(:param_one => 'foo', :session_id => '12345').returns(stub_everything('URI'))
      executor.execute('cmdname', 'http', :param_one => 'foo')
    end
    
    it "should send the URI generated by the created command via HTTP get and return the response" do
      executor = API::CommandExecutor.new(:session_id => '12345')
      command_uri = URI.parse('http://clickatell.com:8080/path?foo=bar')
      API::Command.stubs(:new).returns(command = stub('Command', :with_params => command_uri))
      Net::HTTP.stubs(:new).with(command_uri.host, command_uri.port).returns(http = FakeHttp.new)
      http.stubs(:use_ssl=)
      http.stubs(:get).with('/path?foo=bar').returns([response = stub('HTTP Response'), 'response body'])
      executor.execute('cmdname', 'http').should == response
    end
    
    it "should send the command over a secure HTTPS connection if :secure option is set to true" do
      executor = API::CommandExecutor.new({:session_id => '12345'}, secure = true)
      Net::HTTP.stubs(:new).returns(http = mock('HTTP'))
      http.expects(:use_ssl=).with(true)
      http.stubs(:start).returns([])
      executor.execute('cmdname', 'http')
    end
  end
  
  describe "API" do
    before do
      API.debug_mode = false
      API.secure_mode = false
      API.test_mode = false
      
      @executor = mock('command executor')
      @api = API.new(:session_id => '1234')
      API::CommandExecutor.stubs(:new).with({:session_id => '1234'}, false, false, false).returns(@executor)
    end
    
    it "should use the api_id, username and password to authenticate and return the new session id" do
      @executor.expects(:execute).with('auth', 'http', 
        :api_id => '1234',
        :user => 'joebloggs',
        :password => 'superpass'
      ).returns(response = stub('response'))
      Response.stubs(:parse).with(response).returns('OK' => 'new_session_id')        
      @api.authenticate('1234', 'joebloggs', 'superpass').should == 'new_session_id'
    end
    
    it "should support ping, using the current session_id" do
      @executor.expects(:execute).with('ping', 'http', :session_id => 'abcdefg').returns(response = stub('response'))
      @api.ping('abcdefg').should == response
    end
    
    it "should support sending messages to a specified number, returning the message id" do
      @executor.expects(:execute).with('sendmsg', 'http', 
        :to => '4477791234567',
        :text => 'hello world & goodbye'
      ).returns(response = stub('response'))
      Response.stubs(:parse).with(response).returns('ID' => 'message_id')      
      @api.send_message('4477791234567', 'hello world & goodbye').should == 'message_id'
    end
    
    it "should support sending mms push to a specified number, returning the message id" do
      @executor.expects(:execute).with('ind_push', 'mms',
        :to => '4477791234567',
        :from => "sender",
        :callback => 3,
        :req_feat => '48',
        :mms_subject => 'hello world & goodbye',
        :mms_class => 80,
        :mms_expire => 3000,
        :mms_from => "John",
        :mms_url => "http://www.example.com/content.mms"
      ).returns(response = stub('response'))
      Response.stubs(:parse).with(response).returns('ID' => 'message_id')
      @api.send_mms_push('4477791234567', 'hello world & goodbye', 'http://www.example.com/content.mms', 'John', 3000, 80, :callback => 3, :from => "sender").should == 'message_id'
    end

    it "should support sending messages to a multiple numbers, returning the message ids" do
      @executor.expects(:execute).with('sendmsg', 'http', 
        :to => '4477791234567,447779999999',
        :text => 'hello world & goodbye'
      ).returns(response = stub('response'))
      Response.stubs(:parse).with(response).returns([{'ID' => 'message_1_id'}, {'ID' => 'message_2_id'}])
      @api.send_message(['4477791234567', '447779999999'], 'hello world & goodbye').should == ['message_1_id', 'message_2_id']
    end
    
    it "should set the :from parameter and set the :req_feat to 48 when using a custom from string when sending a message" do
      @executor.expects(:execute).with('sendmsg', 'http', has_entries(:from => 'LUKE', :req_feat => '48')).returns(response = stub('response'))
      Response.stubs(:parse).with(response).returns('ID' => 'message_id')
      @api.send_message('4477791234567', 'hello world', :from => 'LUKE')
    end
    
    it "should set the :mo flag to 1 when :set_mobile_originated is true when sending a message" do
      @executor.expects(:execute).with('sendmsg', 'http', has_entry(:mo => '1')).returns(response=mock('response'))
      Response.stubs(:parse).with(response).returns('ID' => 'message_id')
      @api.send_message('4477791234567', 'hello world', :set_mobile_originated => true)
    end
    
    it "should set the callback flag to the number passed in the options hash" do
      @executor.expects(:execute).with('sendmsg', 'http', has_entry(:callback => 1)).returns(response=mock('response'))
      Response.stubs(:parse).with(response).returns('ID' => 'message_id')
      @api.send_message('4477791234567', 'hello world', :callback => 1)
    end

    it "should set the client message id to the number passed in the options hash" do
      @executor.expects(:execute).with('sendmsg', 'http', has_entry(:climsgid => 12345678)).returns(response=mock('response'))
      Response.stubs(:parse).with(response).returns('ID' => 'message_id')
      @api.send_message('4477791234567', 'hello world', :client_message_id => 12345678)
    end
    
    it "should set the concat flag to the number passed in the options hash" do
      @executor.expects(:execute).with('sendmsg', 'http', has_entry(:concat => 3)).returns(response=mock('response'))
      Response.stubs(:parse).with(response).returns('ID' => 'message_id')
      @api.send_message('4477791234567', 'hello world', :concat => 3)
    end
    
    it "should ignore any invalid parameters when sending a message" do
      @executor.expects(:execute).with('sendmsg', 'http', Not(has_key(:any_old_param))).returns(response = stub('response'))
      Response.stubs(:parse).returns('ID' => 'foo')
      @api.send_message('4477791234567', 'hello world', :from => 'LUKE', :any_old_param => 'test')
    end
    
    it "should support message status query for a given message id, returning the message status" do
      @executor.expects(:execute).with('querymsg', 'http', :apimsgid => 'messageid').returns(response = stub('response'))
      Response.expects(:parse).with(response).returns('ID' => 'message_id', 'Status' => 'message_status')
      @api.message_status('messageid').should == 'message_status'
    end
    
    it "should support balance query, returning number of credits as a float" do
      @executor.expects(:execute).with('getbalance', 'http', {}).returns(response=mock('response'))
      Response.stubs(:parse).with(response).returns('Credit' => '10.0')
      @api.account_balance.should == 10.0
    end

    it "should support delete message for a given message id, returning the message status" do
      @executor.expects(:execute).with('delmsg', 'http', :apimsgid => "messageid").returns(response = stub('response'))
      Response.stubs(:parse).with(response).returns('Status' => 'OK')
      @api.delete_message('messageid').should == 'OK'
    end
    
    it "should raise an API::Error if the response parser raises" do
      @executor.stubs(:execute)
      Response.stubs(:parse).raises(Clickatell::API::Error.new('', ''))
      proc { @api.account_balance }.should raise_error(Clickatell::API::Error)
    end

    describe "when sending a message whit extended ASCII chars" do
      it "should set the unicode flag" do
        @executor.expects(:execute).with('sendmsg', 'http', has_entry(:unicode => 1)).returns(response=mock('response'))
        Response.stubs(:parse).with(response).returns('ID' => 'message_id')
        @api.send_message('4477791234567', 'Há mais línguas no mundo!')
      end

      it "should send message text as unicode" do
        @executor.expects(:execute).with('sendmsg', 'http', has_entries(:unicode => 1, :text => '004800e10020006d0061006900730020006c00ed006e00670075006100730020006e006f0020006d0075006e0064006f0021')).returns(response=mock('response'))
        Response.stubs(:parse).with(response).returns('ID' => 'message_id')
        @api.send_message('4477791234567', 'Há mais línguas no mundo!')
      end

      it "should set the concat flag if message text has more than 70 characters" do
        @executor.expects(:execute).with('sendmsg', 'http', has_entries(:unicode => 1, :concat => 3)).returns(response=mock('response'))
        Response.stubs(:parse).with(response).returns('ID' => 'message_id')
        @api.send_message('4477791234567', 'Há mais línguas no mundo! 日本人は、例えば、いくつかの記号を使用しています。また、中国語、アラブ人、そして他の多くの例がここに引用することができます。いくつかの数学記号、または記号ΩΨΘなどもあります。')
      end
    end

    describe "when sending a message without extended ASCII chars" do
      it "should not set the unicode flag" do
        @executor.expects(:execute).with('sendmsg', 'http', Not(has_entry(:unicode => 1))).returns(response=mock('response'))
        Response.stubs(:parse).with(response).returns('ID' => 'message_id')
        @api.send_message('4477791234567', 'No extended chars here.')
      end

      it "should send message text as is" do
        @executor.expects(:execute).with('sendmsg', 'http', has_entry(:text => 'No extended chars here.')).returns(response=mock('response'))
        Response.stubs(:parse).with(response).returns('ID' => 'message_id')
        @api.send_message('4477791234567', 'No extended chars here.')
      end

      it "should set the concat flag if message text has more than 160 characters" do
        @executor.expects(:execute).with('sendmsg', 'http', has_entries(:concat => 2)).returns(response=mock('response'))
        Response.stubs(:parse).with(response).returns('ID' => 'message_id')
        @api.send_message('4477791234567', 'A very, very long message...'*10)
      end
    end
  end
  
  describe API, ' when authenticating' do
    it "should authenticate to retrieve a session_id and return a new API instance using that session id" do
      API.stubs(:new).returns(api = mock('api'))
      api.stubs(:authenticate).with('my_api_key', 'joebloggs', 'mypassword').returns('new_session_id')
      api.expects(:auth_options=).with(:session_id => 'new_session_id')
      API.authenticate('my_api_key', 'joebloggs', 'mypassword')
    end
  end
  
  describe API, ' with no authentication options set' do
    it "should build commands with no authentication options" do
      api = API.new
      API::CommandExecutor.stubs(:new).with({}, false, false, false).returns(executor = stub('command executor'))
      executor.stubs(:execute)
      api.ping('1234')
    end
  end
  
  describe API, ' in secure mode' do
    it "should execute commands securely" do
      API.secure_mode = true
      api = API.new
      API::CommandExecutor.expects(:new).with({}, true, false, false).returns(executor = stub('command executor'))
      executor.stubs(:execute)
      api.ping('1234')
    end
  end
  
  describe "API Error" do
    it "should parse http response string to create error" do
      response_string = "ERR: 001, Authentication error"
      error = Clickatell::API::Error.parse(response_string)
      error.code.should == '001'
      error.message.should == 'Authentication error'
    end
  end
  
  describe API, "#test_mode" do
    before(:each) do
      API.secure_mode = false
      API.test_mode = true
      @api = API.new
    end
    
    it "should create a new CommandExecutor with test_mode parameter set to true" do
      API::CommandExecutor.expects(:new).with({}, false, false, true).once.returns(executor = mock('command executor'))
      executor.stubs(:execute)
      executor.stubs(:sms_requests).returns([])
      @api.ping('1234')
    end
    
    it "should record all commands" do
      @api.ping('1234')
      @api.sms_requests.should_not be_empty
    end
    
    it "should return the recorded commands in a flattened array" do
      @api.ping('1234')
      @api.sms_requests.size.should == 1
      @api.sms_requests.first.should_not be_instance_of(Array)
    end
  end
  
end