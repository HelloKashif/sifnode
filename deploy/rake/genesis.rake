desc ""
namespace :genesis do
  desc "network operations"
  namespace :network do
    desc "Scaffold a new genesis network for use in docker-compose"
    task :scaffold, [:chainnet] do |t, args|
      if args[:chainnet].nil?
        puts "Please provide chainnet argument. ie testnet, mainnet"
        exit 1
      end

      network_create(chainnet: args[:chainnet], validator_count: 1, build_dir: "#{cwd}/../networks",
                     seed_ip_address: "192.168.2.1",network_config: network_config(args[:chainnet]))
    end

    desc "Boot the new scaffolded network in docker-compose"
    task :boot, [:chainnet, :eth_bridge_registry_address, :eth_keys, :eth_websocket] do |t, args|
      trap('SIGINT') { puts "Exiting..."; exit }

      if args[:chainnet].nil?
        puts "Please provide chainnet argument. ie testnet, mainnet"
        exit(1)
      end

      with_eth = eth_config(eth_bridge_registry_address: args[:eth_bridge_registry_address],
                            eth_keys: args[:eth_keys].split(" "),
                            eth_websocket: args[:eth_websocket])

      if !File.file?(network_config(args[:chainnet]))
        puts "the file #{network_config(args[:chainnet])} does not exist!"
        exit(1)
      end

      build_docker_image(args[:chainnet])
      boot_docker_network(chainnet: args[:chainnet], seed_network_address: "192.168.2.0/24", eth_config: with_eth)
    end

    desc "Expose local seed node to the outside world"
    task :expose, [:chainnet] do |t, args|
      puts "Build me!" # TODO use something like ngrok to expose local ports of seed node to the world
    end

    desc "Reset the state of a network"
    task :reset, [:chainnet] do |t, args|
      system("sifgen network reset #{args[:chainnet]} #{cwd}/../networks")
    end
  end

  desc "node operations"
  namespace :sifnode do
    desc "Scaffold a new local node and configure it to connect to an existing network"
    task :scaffold, [:chainnet, :peer_address, :genesis_url] do |t, args|
      system("sifgen node create #{args[:chainnet]} #{args[:peer_address]} #{args[:genesis_url]}")
    end

    desc "boot scaffolded node and connect to existing network"
    task :boot do
      system("sifnoded start --p2p.laddr tcp://0.0.0.0:26658 ")
    end

    desc "Reset the state of a node"
    task :reset, [:chainnet, :node_directory] do |t, args|
      system("sifgen node reset #{args[:chainnet]} #{args[:node_directory]}")
    end
  end
end

#
# Creates the config for a new network
#
# @param chainnet           Name or ID of the chain
# @param validator_count    Number of validators to configure
# @param build_dir          Path to the build directory
# @param seed_ip_address    IPv4 address of the first node
# @param network_config     Name of the file to use to output the config to
#
def network_create(chainnet:, validator_count:, build_dir:, seed_ip_address:, network_config:)
  system("sifgen network create #{chainnet} #{validator_count} #{build_dir} #{seed_ip_address} #{network_config}")
end

#
# Boot the new network
#
# @param chainnet               Name or ID of the chain
# @param seed_network_address   Network address w/netmask (e.g.: 192.168.1.0/24)
# @param eth_config             Ethereum configuration (bridge address and private keys)
#
def boot_docker_network(chainnet:, seed_network_address:, eth_config:)
  network = YAML.load_file(network_config(chainnet))

  cmd = "CHAINNET=#{chainnet} "
  network.each_with_index do |node, idx|
    cmd += "MONIKER#{idx+1}=#{node['moniker']} MNEMONIC#{idx+1}=\"#{node['mnemonic']}\" IPV4_ADDRESS#{idx+1}=#{node['ipv4_address']} "
  end

  cmd += "IPV4_SUBNET=#{seed_network_address} #{eth_config} docker-compose -f #{cwd}/../genesis/docker-compose.yml up"
  system(cmd)
end

#
# Build docker image for the new network
#
# @param chainnet Name or ID of the chain
#
def build_docker_image(chainnet)
  system("docker build -f #{cwd}/../genesis/Dockerfile -t sifchain/sifnoded:#{chainnet} #{cwd}/../../")
end

#
# Ethereum config
#
# @param eth_bridge_registry_address    Ethereum bridge registry address
# @param eth_keys                       Ethereum private keys
# @param eth_websocket                  Ethereum websocket address to listen to
#
def eth_config(eth_bridge_registry_address:, eth_keys:, eth_websocket:)
  config = "ETHEREUM_CONTRACT_ADDRESS=#{eth_bridge_registry_address} "

  eth_keys.each_with_index do |address, idx|
    config += " ETHEREUM_PRIVATE_KEY#{idx+1}=#{eth_keys[idx]} "
  end

  config += "ETHEREUM_WEBSOCKET_ADDRESS=#{eth_websocket}"
  return config
end
