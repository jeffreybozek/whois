#--
# Ruby Whois
#
# An intelligent pure Ruby WHOIS client and parser.
#
# Copyright (c) 2009-2011 Simone Carletti <weppos@weppos.net>
#++


require 'whois/record/parser/base'
require 'whois/record/parser/scanners/base'


module Whois
  class Record
    class Parser

      #
      # = whois.nic.hu parser
      #
      # Parser for the whois.nic.hu server.
      #
      # @author Simone Carletti <weppos@weppos.net>
      # @author Gábor Vészi <veszig@done.hu>
      #
      class WhoisNicHu < Base
        include Features::Ast

        property_supported :disclaimer do
          node("disclaimer")
        end


        property_supported :domain do
          node("domain")
        end

        property_supported :domain_id do
          node('hun-id')
        end


        property_supported :status do
          if node("status-available")
            :available
          elsif node("status-inprogress")
            :registered
          else
            :registered
          end
        end

        property_supported :available? do
          status == :available
        end

        property_supported :registered? do
          !available?
        end


        property_supported :created_on do
          node('registered') { |raw| Time.parse(raw) }
        end

        property_supported :updated_on do
          node('changed') { |raw| Time.parse(raw) }
        end

        property_not_supported :expires_on


        property_supported :registrar do
          if c = registrar_contact
            Record::Registrar.new(
              :id => c[:id],
              :name => c[:name],
              :organization => c[:organization]
            )
          end
        end

        property_supported :registrant_contacts do
          return unless node("name")

          address, city, zip, country_code = decompose_address(node("address"))

          Whois::Record::Contact.new(
            :type         => Whois::Record::Contact::TYPE_REGISTRANT,
            :name         => node("name"),
            :organization => node("org"),
            :address      => address,
            :city         => city,
            :zip          => zip,
            :country_code => country_code,
            :phone        => node("phone"),
            :fax          => node("fax-no")
          )
        end

        property_supported :admin_contacts do
          contact("admin-c", Whois::Record::Contact::TYPE_ADMIN)
        end

        property_supported :technical_contacts do
          contact("tech-c", Whois::Record::Contact::TYPE_TECHNICAL)
        end


        property_supported :nameservers do
          Array.wrap(node("nameserver")).map do |name|
            Record::Nameserver.new(name)
          end
        end


        # NEWPROPERTY
        def registrar_contact
          cached_properties_fetch(:registrar_contact) do
            contact("registrar", nil)
          end
        end

        # NEWPROPERTY
        def zone_contact
          cached_properties_fetch(:zone_contact) do
            contact("zone-c", nil)
          end
        end


        # Initializes a new {Scanner} instance
        # passing the {Whois::Record::Parser::Base#content_for_scanner}
        # and calls +parse+ on it.
        #
        # @return [Hash]
        def parse
          Scanner.new(content_for_scanner).parse
        end


        protected

          def contact(element, type)
            node(node(element)) do |raw|
              Whois::Record::Contact.new do |c|
                c.type = type
                raw.each { |k,v| c[k.to_sym] = v }
              end
            end
          end

          # Depending on record type, the address can be <tt>nil</tt>
          # or an array containing different address parts.
          def decompose_address(parts)
            addresses = parts || []
            address, city, zip, country_code = nil, nil, nil, nil

            if !addresses.empty?
              address       = addresses[0]                if addresses[0]
              zip, city     = addresses[1].split(" ", 2)  if addresses[1]
              country_code  = addresses[2]                if addresses[2]
            end

            [address, city, zip, country_code]
          end


        class Scanner < Scanners::Base

          def parse_content
            parse_version     ||
            parse_disclaimer  ||
            parse_domain      ||
            parse_available   ||
            parse_in_progress ||

            # v2.0
            parse_moreinfo    ||

            # v1.99
            parse_domain_data ||
            parse_contacts    ||

            trim_empty_line   ||
            error!("Unexpected token")
          end


          def parse_version
            if @input.match?(/% Whois server .*\n/)
              p("whois.nic.hu: parse_version") if 1 == 2 || $DEBUG
              @input.scan(/% Whois server ([\w\d\.]*).*?\n/)
              @ast["version"] = @input[1]
            end
          end

          # FIXME: Requires UTF-8 Encoding (see #11)
          def parse_moreinfo
            if @input.match?(/Tov.* ld\.:\n/)
              p("whois.nic.hu: parse_moreinfo") if 1 == 2 || $DEBUG
              @ast["moreinfo"] = @input.scan_until(/^\n/)
            end
          end

          def parse_disclaimer
            if @input.match?(/^Rights.*\n/)
              p("whois.nic.hu: parse_disclaimer") if 1 == 2 || $DEBUG
              lines = @input.scan_until(/^\n/)
              @ast["disclaimer"] = lines.strip
            end
          end

          def parse_domain
            if @input.match?(/^domain:\s+(.*)\n/) && @input.scan(/^domain:\s+(.*?)\n/)
              p("whois.nic.hu: parse_domain") if 1 == 2 || $DEBUG
              @ast["domain"] = @input[1].strip
            end
          end

          # FIXME: Requires UTF-8 Encoding (see #11)
          def parse_available
            if @input.match?(/Nincs (.*?) \/ No match\n/)
              p("whois.nic.hu: parse_not_found") if 1 == 2 || $DEBUG
              @input.scan(/Nincs (.*?) \/ No match\n/)
              @ast["status-available"] = true
            end
          end

          # FIXME: Requires UTF-8 Encoding (see #11)
          def parse_in_progress
            if @input.match?(/(.*?) folyamatban \/ Registration in progress\n/)
              p("whois.nic.hu: parse_in_progress") if 1 == 2 || $DEBUG
              @input.scan(/(.*?) folyamatban \/ Registration in progress\n/)
              @ast["status-inprogress"] = true
            end
          end

          def parse_domain_data
            if @input.match?(/(.+?):\s+(.*)\n/)
              p("whois.nic.hu: parse_domain_data") if 1 == 2 || $DEBUG
              while @input.scan(/(.+?):\s+(.*)\n/)
                key, value = @input[1].strip, @input[2].strip
                if key == 'person'
                  @ast['name'] = value
                elsif key == 'org'
                  if value =~ /org_name_hun:\s+(.*)\Z/
                    @ast['name'] = $1
                  elsif value =~ /org_name_eng:\s+(.*)\Z/
                    @ast['org'] = $1
                  elsif value != 'Private person'
                    contact['org'] = value
                  end
                elsif @ast[key].nil?
                  @ast[key] = value
                elsif @ast[key].is_a? Array
                  @ast[key] << value
                else
                  @ast[key] = [@ast[key], value].flatten
                end
              end
              true
            end
          end

          def parse_contacts
            if @input.match?(/\n(person|org):/)
              p("whois.nic.hu: parse_contacts") if 1 == 2 || $DEBUG
              @input.scan(/\n/)
              while @input.match?(/(.+?):\s+(.*)\n/)
                parse_contact
              end
              true
            end
          end

          def parse_contact
            contact ||= {}
            p("whois.nic.hu: parse_contact") if 1 == 2 || $DEBUG
            while @input.scan(/(.+?):\s+(.*)\n/)
              key, value = @input[1].strip, @input[2].strip
              if key == 'hun-id'
                a1 = contact['address'][1].split(/\s/)
                zip = a1.shift
                city = a1.join(' ')
                # we should keep the old values if this is an already
                # defined contact
                if @ast[value].nil?
                  @ast[value] = {
                    "id" => value,
                    "name" => contact['name'],
                    "organization" => contact['org'],
                    "address" => contact['address'][0],
                    "city" => city,
                    "zip" => zip,
                    "country_code" => contact['address'][2],
                    "phone" => contact['phone'],
                    "fax" => contact['fax-no'],
                    "email" => contact['e-mail']
                  }
                else
                  @ast[value]["id"] ||= value
                  @ast[value]["name"] ||= contact['name']
                  @ast[value]["organization"] ||= contact['org']
                  @ast[value]["address"] ||= contact['address'][0]
                  @ast[value]["city"] ||= city
                  @ast[value]["zip"] ||= zip
                  @ast[value]["country_code"] ||= contact['address'][2]
                  @ast[value]["phone"] ||= contact['phone']
                  @ast[value]["fax"] ||= contact['fax-no']
                  @ast[value]["email"] ||= contact['e-mail']
                end
                contact = {}
              elsif key == 'person'
                contact['name'] = value
              elsif key == 'org'
                if value =~ /org_name_hun:\s+(.*)\Z/
                  contact['name'] = $1
                elsif value =~ /org_name_eng:\s+(.*)\Z/
                  contact['org'] = $1
                else
                  contact['org'] = value
                end
              elsif key == 'address' && !contact['address'].nil?
                contact['address'] = [contact['address'], value].flatten
              else
                contact[key] = value
              end
            end
            true
          end

        end

      end

    end
  end
end
