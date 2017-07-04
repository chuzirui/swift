#!/bin/bash

if [ $# -ne 1 ]; then
    echo $0: usage ./install.sh [swift/noswift/noswiftp4]
    exit 1
fi

if [ "$1" == "swift" ]
    then cp -r ~/SWIFT/swift/lab/quagga_config/configs_swift/* ~/miniNExT/examples/swift/configs/
elif [[ "$1" == "noswift" ]] || [[ "$1" == "noswiftp4" ]]
    then cp -r ~/SWIFT/swift/lab/quagga_config/configs_noswift/* ~/miniNExT/examples/swift/configs/
else
    echo $0: usage ./install.sh [swift/noswift]
fi

sleep 1


killall ovs-controller > /dev/null 2>&1
tmux kill-session -t mininext &> /dev/null
tmux new-session -d -s mininext

if [ "$1" == "noswiftp4" ]
    then tmux send -t mininext "sudo python /root/miniNExT/examples/swift/start.py --sw_path /root/behavioral-model/targets/simple_switch/simple_switch --json_path /root/SWIFT/swift/lab/p4/swift.json" ENTER
else
    tmux send -t mininext "sudo python /root/miniNExT/examples/swift/start.py" ENTER
fi

sleep 2
echo '-- Virtual topology started!'

if [[ "$1" == "swift" ]] || [[ "$1" == "noswift" ]]; then

    ovs-vsctl set-controller s1 tcp:127.0.0.1:6633
    ovs-vsctl set-fail-mode s1 secure
    ifconfig s1 2.0.0.4/24 up

    sleep 1

    r2_port=`ovs-ofctl show s1 | grep r2-ovs | cut -f 1 -d '(' | tr -d ' '`
    r3_port=`ovs-ofctl show s1 | grep r3-ovs | cut -f 1 -d '(' | tr -d ' '`
    r4_port=`ovs-ofctl show s1 | grep r4-ovs | cut -f 1 -d '(' | tr -d ' '`

    echo '2.0.0.1   20:00:00:00:00:01   '$r2_port > /root/SWIFT/swift/main/mapping
    echo '2.0.0.2   20:00:00:00:00:02   '$r3_port >> /root/SWIFT/swift/main/mapping
    echo '2.0.0.3   20:00:00:00:00:03   '$r4_port >> /root/SWIFT/swift/main/mapping

    sudo ovs-ofctl add-flow s1 priority=1000,dl_type=0x0806,in_port=$r2_port,actions=output:$r3_port,$r4_port,Controller
    sudo ovs-ofctl add-flow s1 priority=1000,dl_type=0x0806,in_port=$r3_port,actions=output:$r2_port,$r4_port,Controller
    sudo ovs-ofctl add-flow s1 priority=1000,dl_type=0x0806,in_port=$r4_port,actions=output:$r2_port,$r3_port,Controller
    sudo ovs-ofctl add-flow s1 priority=1000,dl_type=0x0806,in_port=LOCAL,actions=output:$r2_port,$r3_port,$r4_port

    sudo ovs-ofctl add-flow s1 priority=1000,dl_type=0x0800,dl_dst=20:00:00:00:00:01,actions=output:$r2_port
    sudo ovs-ofctl add-flow s1 priority=1000,dl_type=0x0800,dl_dst=20:00:00:00:00:02,actions=output:$r3_port
    sudo ovs-ofctl add-flow s1 priority=1000,dl_type=0x0800,dl_dst=20:00:00:00:00:03,actions=output:$r4_port
    sudo ovs-ofctl add-flow s1 priority=1000,dl_type=0x0800,dl_dst=20:00:00:00:00:04,actions=output:LOCAL

    ip link set dev s1 address 20:00:00:00:00:04

    sleep 2
    echo '-- OVS ready!'
fi

./mx r6 '/root/bgpsimple/bgp_simple.pl -myip 6.0.0.2 -myas 60 -peerip 6.0.0.1 -peeras 50 -holdtime 1200 -keepalive 400 -p /root/bgpsimple/bgpdump/bview_200K &' 1> /root/.bgpsimple_r6_output

sleep 1
echo '-- BGPsimple started!'

if [ "$1" == "swift" ]
then
    tmux kill-session -t floodlight &> /dev/null
    tmux new-session -d -s floodlight
    tmux send -t floodlight "cd floodlight && java -jar target/floodlight.jar" ENTER

    sleep 1
    echo '-- Floodlight started! [for SWIFT]'

    tmux kill-session -t exabgp &> /dev/null
    ./.kill_exabgp.sh &> /dev/null
    tmux new-session -d -s exabgp
    tmux send -t exabgp 'env exabgp.tcp.bind="127.0.0.1" exabgp.tcp.port=179 exabgp.daemon.drop=false exabgp.log.level=WARNING ~/exabgp/sbin/exabgp ~/SWIFT/swift/lab/exabgp/exabgp-rs.conf
    ' ENTER

    echo '-- EXABGP started! [for SWIFT]'
fi

#nping --dest-ip 12.27.33.1 -H --rate 10 -c 4000