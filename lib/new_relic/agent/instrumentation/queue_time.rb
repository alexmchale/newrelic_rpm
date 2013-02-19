module NewRelic
  module Agent
    module Instrumentation
      # https://newrelic.com/docs/features/tracking-front-end-time
      # Record queue time metrics based on any of three headers
      # which can be set on the request.
      module QueueTime
        unless defined?(REQUEST_START_HEADER)
          REQUEST_START_HEADER    = 'HTTP_X_REQUEST_START'
          QUEUE_START_HEADER      = 'HTTP_X_QUEUE_START'
          QUEUE_DURATION_HEADER   = 'HTTP_X_QUEUE_TIME'
          MIDDLEWARE_START_HEADER = 'HTTP_X_MIDDLEWARE_START'
          ALL_QUEUE_METRIC        = 'WebFrontend/QueueTime'
          # any timestamps before this are thrown out and the parser
          # will try again with a larger unit (2000/1/1 UTC)
          EARLIEST_ACCEPTABLE_TIMESTAMP = 946684800
        end

        module_function

        def parse_frontend_timestamp(headers, now=Time.now)
          candidate_headers = [ REQUEST_START_HEADER, QUEUE_START_HEADER,
                                MIDDLEWARE_START_HEADER ]
          earliest = candidate_headers.map do |header|
            if headers[header]
              parse_timestamp(timestamp_string_from_header_value(headers[header]))
            end
          end.compact.min

          if earliest && earliest > now
            NewRelic::Agent.logger.debug("Negative queue time detected, treating as zero: start=#{earliest.to_f} > now=#{now.to_f}")
            earliest = now
          end

          earliest
        end

        def record_frontend_metrics(start_time, now=Time.now)
          NewRelic::Agent.instance.stats_engine.get_stats(ALL_QUEUE_METRIC) \
            .record_data_point((now - start_time).to_f)
        end

        def timestamp_string_from_header_value(value)
          case value
          when /^\s*([\d+\.]+)\s*$/ then $1
          # following regexp intentionally unanchored to handle
          # (ie ignore) leading server names
          when /t=([\d+\.]+)/       then $1
          end
        end

        def parse_timestamp(string)
          cut_off = Time.at(EARLIEST_ACCEPTABLE_TIMESTAMP)
          [1_000_000, 1_000, 1].map do |divisor|
            Time.at(string.to_f / divisor)
          end.find {|candidate| candidate > cut_off }
        end
      end
    end
  end
end
