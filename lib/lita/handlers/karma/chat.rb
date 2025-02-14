module Lita::Handlers::Karma
  # Tracks karma points for arbitrary terms.
  class Chat < Lita::Handler
    namespace "karma"

    on :loaded, :define_routes

    def define_routes(payload)
      define_static_routes
      define_dynamic_routes(config.term_pattern.source)
    end

    def increment(response)
      modify(response, :increment)
    end

    def increment_and_react(response)
      modify(response, :increment, true)
    end

    def decrement(response)
      modify(response, :decrement)
    end

    def check(response)
      seen = Set.new

      output = response.matches.map do |match|
        term = get_term(match[0])
        next if seen.include?(term)
        seen << term
        term.check(true)
      end.compact

      response.reply "…#{output.join("; ")}"
    end

    def list_best(response)
      list(response, :list_best)
    end

    def list_worst(response)
      list(response, :list_worst)
    end

    def link(response)
      response.matches.each do |match|
        term1 = get_term(match[0])
        term2 = get_term(match[1])

        result = term1.link(term2)

        case result
        when Integer
          response.reply t("threshold_not_satisfied", threshold: result)
        when true
          response.reply t("link_success", source: term2, target: term1)
        else
          response.reply t("already_linked", source: term2, target: term1)
        end
      end
    end

    def unlink(response)
      response.matches.each do |match|
        term1 = get_term(match[0])
        term2 = get_term(match[1])

        if term1.unlink(term2)
          response.reply t("unlink_success", source: term2, target: term1)
        else
          response.reply t("already_unlinked", source: term2, target: term1)
        end
      end
    end

    def modified(response)
      term = get_term(response.args[1])

      users = term.modified

      if users.empty?
        response.reply t("never_modified", term: term)
      else
        response.reply users.map(&:name).join(", ")
      end
    end

    def delete(response)
      term = Term.new(robot, response.message.body.sub(/^karma delete /, ""), normalize: false)

      if term.delete
        response.reply t("delete_success", term: term)
      end
    end

    private

    def define_dynamic_routes(pattern)
      self.class.route(
        %r{(#{pattern})\+\+#{token_terminator.source}},
        :increment_and_react,
        help: { t("help.increment_key") => t("help.increment_value") }
      )

      self.class.route(
        %r{(#{pattern})--#{token_terminator.source}},
        :decrement,
        help: { t("help.decrement_key") => t("help.decrement_value") }
      )

      self.class.route(
        %r{(#{pattern})~~#{token_terminator.source}},
        :check,
        help: { t("help.check_key") => t("help.check_value") }
      )

      self.class.route(
        %r{^(#{pattern})\s*\+=\s*(#{pattern})(?:\+\+|--|~~)?#{token_terminator.source}},
        :link,
        command: true,
        help: { t("help.link_key") => t("help.link_value") }
      )

      self.class.route(
        %r{^(#{pattern})\s*-=\s*(#{pattern})(?:\+\+|--|~~)?#{token_terminator.source}},
        :unlink,
        command: true,
        help: { t("help.unlink_key") => t("help.unlink_value") }
      )
    end

    def define_static_routes
      self.class.route(
        %r{^karma\s+worst},
        :list_worst,
        command: true,
        help: { t("help.list_worst_key") => t("help.list_worst_value") }
      )

      self.class.route(
        %r{^karma\s+best},
        :list_best,
        command: true,
        help: { t("help.list_best_key") => t("help.list_best_value") }
      )

      self.class.route(
        %r{^karma\s+modified\s+.+},
        :modified,
        command: true,
        help: { t("help.modified_key") => t("help.modified_value") }
      )

      self.class.route(
        %r{^karma\s+delete},
        :delete,
        command: true,
        restrict_to: :karma_admins,
        help: { t("help.delete_key") => t("help.delete_value") }
      )

      self.class.route(%r{^karma\s*$}, :list_best, command: true)
    end

    def determine_list_count(response)
      n = (response.args[1] || 5).to_i - 1
      n = 25 if n > 25
      n
    end

    def get_term(term)
      Term.new(robot, term)
    end

    def list(response, method_name)
      terms_and_scores = Term.public_send(method_name, robot, determine_list_count(response))

      output = terms_and_scores.each_with_index.map do |term_and_score, index|
        "#{index + 1}. #{term_and_score[0]} (#{term_and_score[1].to_i})"
      end.join("\n")

      if output.empty?
        response.reply t("no_terms")
      else
        response.reply output
      end
    end

    def modify(response, method_name, should_react=false)
      user = response.user
      messages_for_reply = []

      output = response.matches.map do |match|
        get_term(match[0]).public_send(method_name, user)
      end

      if should_react

        # If multiple terms were modified, we respond in a thread
        if output.length > 1
          # the "…" will make `lita-slack` thread the response.
          messages_for_reply << ["…#{output.join(", ")}"]
        end

        # grab the overall count from a string like: "jeff: 4361 (4063),"
        regex = /\b:\s(\d+)/
        match = output.first&.match(regex)
        total_points = match&.captures&.first

        if total_points
          # If only one person got points, we react to the original message with
          # emojis rather than a threaded reply
          if output.length === 1
            emojis = [:zero, :one, :two, :three, :four, :five, :six, :seven, :eight, :nine].map {|emoji|
              ['', :_v2, :_v3, :_v4].map { |v|
                "#{emoji}#{v}".to_sym
              }
            }

            numbers = total_points.split('').map(&:to_i).map { |n|
              emojis[n].shift
            }

            messages_for_reply << numbers
          end

          celebration_emojis = [
            'raised-hands',
            'party-wizard',
            'hands',
            'tada',
            'confetti_ball',
            'partyblob',
            'partyparrot',
          ]

          reaction_for_points = {
            '100' => '100',
            '420' => '420',
            '9000' => '9000',
            '666' => 'blob-devil',
            '1000' => '1000',
            '10' => celebration_emojis.sample,
            '50' => celebration_emojis.sample,
            '1' => celebration_emojis.sample,
          }[total_points]

          if !reaction_for_points && total_points.to_i % 100 === 0
            reaction_for_points = celebration_emojis.sample
          end

          if reaction_for_points
            messages_for_reply << reaction_for_points.to_sym
          end
        end
      end

      response.reply messages_for_reply
    end

    # To ensure that constructs like foo++bar or foo--bar (the latter is
    # common in some URL generation schemes) do not cause errant karma
    # modifications, force karma tokens be followed by whitespace (in a zero-
    # width, look-ahead operator) or the end of the string.
    def token_terminator
      %r{(?:(?=[[:space:]])|$)}
    end
  end
end

Lita.register_handler(Lita::Handlers::Karma::Chat)
