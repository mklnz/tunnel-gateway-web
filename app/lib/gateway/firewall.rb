module Gateway
  class Firewall < Base
    include Singleton

    CHNROUTE_FILE = File.expand_path('../../../shared/chnroute_ipset.txt', __FILE__)

    def ss_config
      Shadowsocks.instance.ss_config
    end

    def switch_mode(mode)
      case mode
      when 'disabled', ''
        set_direct
      when 'blocked_servers'
        set_blocked
      when 'foreign_servers'
        set_foreign
      when 'all_servers'
        set_global
      end
    end

    def setup
      %x(
        sudo ipset -N gfwlist hash:ip
        sudo ipset -N chnroute hash:net
        sudo ipset -N direct hash:net
      )
      add_dns_ipset
    end

    def clean
      set_direct
      %x(
        sudo ipset destroy gfwlist
        sudo ipset destroy chnroute
      )
    end

    def set_direct
      %x(
        sudo iptables -F
        sudo iptables -X
        sudo iptables -t nat -F
        sudo iptables -t nat -X
      )

      flush_ipset
    end

    def flush_ipset
      %x(
        sudo ipset flush gfwlist
        sudo ipset flush chnroute
      )
      add_dns_ipset
    end

    def add_to_set(set, host)
      %x(
        sudo ipset add #{set} #{host}
      )
    end

    def set_global
      pre_rules
      `sudo iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-port #{ss_config['local_port']}`
      commit_rules
    end

    def set_blocked
      pre_rules
      `sudo iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-port #{ss_config['local_port']}`
      commit_rules
    end

    def set_foreign
      pre_rules
      %x(
        sudo ipset restore < #{CHNROUTE_FILE}
        sudo iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set chnroute dst -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-port #{ss_config['local_port']}
      )
      commit_rules
    end

    private

    def add_dns_ipset
      %x(
        sudo ipset add gfwlist 8.8.8.8
        sudo ipset add gfwlist 8.8.4.4
      )
    end

    def pre_rules
      set_direct
      %x(
        sudo iptables -t nat -N SHADOWSOCKS
        sudo iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -d 10.0.0.0/8 -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -d 127.0.0.0/8 -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -d 169.254.0.0/16 -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -d 172.16.0.0/12 -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -d 192.168.0.0/16 -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -d 224.0.0.0/4 -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -d 240.0.0.0/4 -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -d #{ss_config['server']} -j RETURN
        sudo iptables -t nat -A SHADOWSOCKS -m set --match-set direct dst -j RETURN
      )
    end

    def commit_rules
      %x(
        sudo iptables -t nat -A OUTPUT -p tcp -j SHADOWSOCKS
        sudo iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS
      )
    end
  end
end
