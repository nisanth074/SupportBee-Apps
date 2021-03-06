module CapsuleCrm
  module EventHandler
    # Handle 'ticket.created' event
    def ticket_created
      ticket = payload.ticket
      requester = ticket.requester 
      http.basic_auth(settings.api_token, "")

      begin
        person = find_person(requester)  
        unless person
          return [200, 'Contact creation deisabled'] unless settings.should_create_person.to_s == '1'
          person =  create_new_person(ticket, requester)
          html = new_person_info_html(person)
        else
          html = person_info_html(person)
          send_note(ticket, person)
        end
      rescue Exception => e
        puts "#{e.message}\n#{e.backtrace}"
        [500, e.message]
      end
      
      comment_on_ticket(ticket, html)
      [200, "Ticket sent to Capsulecrm"]
    end
  end
end

module CapsuleCrm
  class Base < SupportBeeApp::Base
    string :api_token, :required => true, :label => 'Capsule Auth Token', :hint => 'Login to your Capsule account, go to My Preferences (in the User Menu) > API Authentication Token'
    string :subdomain, :required => true, :hint => 'If your Capsule Crm URL is "https://something.capsulecrm.com" then your Subdomain value is "something'
    boolean :should_create_person, :default => true, :required => false, :label => 'Create a New Person in Capsule if one does not exist'
    boolean :return_ticket_content, :required => false, :label => 'Send ticket content to Capsule'
	
    white_list :should_create_person, :subdomain

    def find_person(requester)
      first_name = split_name(requester)
      response = http_get "https://#{settings.subdomain}.capsulecrm.com/api/party" do |req|
        req.headers['Accept'] = 'application/json'
        req.params['email'] = requester.email
      end
      body = response.body if response.status == 200
      person = body['parties']['person'] if body
      person ? person : nil
    end
 
    def create_new_person(ticket, requester)
      location = create_person(requester)
      note_to_new_person(location, ticket)
      get_person(location)
    end

    def create_person(requester)
      return unless settings.should_create_person.to_s == '1'
      first_name = split_name(requester)
      response = http_post "https://#{settings.subdomain}.capsulecrm.com/api/person" do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = {person:{firstName:first_name, contacts:{email:{emailAddress:requester.email}}}}.to_json
      end
      location = response['location']
    end

    def send_note(ticket, person)
      person_id = person['id']
      http_post "https://#{settings.subdomain}.capsulecrm.com/api/party/#{person_id}/history" do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = {historyItem:{note:generate_note_content(ticket)}}.to_json
      end
    end
    
    def note_to_new_person(location, ticket)
      http_post "#{location}/history" do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = {historyItem:{note:generate_note_content(ticket)}}.to_json
      end
    end

    def split_name(requester)
      first_name, last_name = requester.name ? requester.name.split(' ') : [requester.email,'']
      return first_name
    end

    def get_person(location)
      response = http_get "#{location}" do |req|
        req.headers['Accept'] = 'application/json'
        end
      person = response.body['person']
    end
      
    def person_info_html(person)
      html = ""
      html << "<b> #{person['firstName']} </b><br/>" 
      html << "#{person['title']} " if person['title']
      html << "<br/>"
      html << person_link(person)
      html
    end

    def new_person_info_html(person)
      html = "Added #{person['firstName']} to Capsule...<br/> "
      html << person_link(person)
      html
    end

    def person_link(person)
      "<a href='https://#{settings.subdomain}.capsulecrm.com/party/#{person['id']}'>View #{person['firstName']}'s profile on capsule</a>"
    end
   
    def comment_on_ticket(ticket, html)
        ticket.comment(:html => html)
    end
   
    def generate_note_content(ticket)
      note = ""
      note << ticket.summary + "\n" if settings.return_ticket_content.to_s == '1'
      note << "https://#{auth.subdomain}.supportbee.com/tickets/#{ticket.id}"
    end
     
  end
 end

