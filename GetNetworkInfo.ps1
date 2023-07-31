#####################################################################################################################
### Программа построения карты локальной сети 
### На вход: 
###       $DirectoryLOGs\sw-mac.csv -- список управляемых коммутаторов в csv-формате <SwitchName>;<IP>;<MAC(as ff-ee-cc-00-11-22)>
###
###
#####################################################################################################################


param(
    [Parameter(Mandatory=$false)][string]   $MainGW        = '192.168.122.8' ,
    [Parameter(Mandatory=$false)][string]   $OutReport = 'C:\Working\mac-ip-sw\NewProjectWithClasses\LAN_MAP#.csv' ,
    [Parameter(Mandatory=$false)][string]   $SwitchListCSV = "C:\Working\mac-ip-sw\NewProjectWithClasses\switches-fresh.csv" ,
    [Parameter(Mandatory=$false)][string]   $SNMP_UTIL     = 'D:\public\SNMPUTIL\Snmputil.exe' 
); 

Class CSwitchPort{
    [String]                       $portID;    # Обозначение порта (Logical Name)
    [String]                       $physicalPort; 
    [Boolean]                      $isUpLink; # есть ли за этим портом коммутаторы 
    [CSwitch]                      $switch;
    [System.Collections.ArrayList] $port_MACs; # таблица хостов за этим портом 

    CSwitchPort([String] $inPortID, [String] $inPhysicalPort, [CSwitch] $mySwitch){
        $this.switch = $mySwitch; 
        $this.portID = $inPortID; 
        $this.physicalPort = $inPhysicalPort; 
        $this.isUpLink = $false; # по-умолчанию порт не upLink 
        $this.port_MACs = New-Object System.Collections.ArrayList($null);
    }
    
    [String] getPhysicalPort(){
        return $this.physicalPort; 
    }

    [String] getPortID(){
        return $this.portID; 
    }

    [void] addMAC([CHost]$MAC){
        # Если данный mac-адрес не существует еще в таблице адресов порта -- добавить его
        if(-not $this.port_MACs.Contains($MAC)){
            $this.port_MACs.Add($MAC) ;
            # Если хост, добавляемый в таблицу порта, -- коммутатор, то порт становится uplink
            if($MAC.getIsSwitch()){
                $this.isUpLink = $true ; 
            }
        }
    }

    [void] deleteMAC([CHost] $Private:HostToDelte) {
        if($this.port_MACs.Contains($Private:HostToDelte)){
            if('0cc47a7848fc' -like $HostToDelte.getMAC()){ 
                Write-Host ("Switch {0} port {1} delete mac {2} from table" -f $this.switch.switch_host.getDNSName(), $this.portID, $Private:HostToDelte.getMAC()) ;
            }
            $this.port_MACs.Remove($Private:HostToDelte) ;
        }
    }

    [CSwitch[]] getSwitchesBehindPort() {
        return $this.port_MACs.Where({([CHost]$_).getIsSwitch()}) | Select-Object -ExpandProperty host_is_switch_link;
    }

    [CSwitch[]] getSwitchesBehindPortWithMe() {
        return @($this.switch) + $this.getSwitchesBehindPort() ;
    }

    [boolean] getIsUpLink(){
        return $this.isUpLink; 
    }
}

Class CARP{

    [String] $mac_address; 


}

Class CHost{
    [String]  $host_mac; 
    [String]  $host_ip; 
    [boolean] $host_is_switch; 
    [CSwitch] $host_is_switch_link; 
    [String]  $host_DNS_name; 

    CHost([String] $MAC, [String] $IP=$null, [boolean] $IsSwitch=$false){
        $this.host_mac = [CHost]::macParse($MAC); 
        $this.host_is_switch = $isSwitch;
        $this.host_is_switch_link = $null;
        $this.host_ip = $IP;
        $this.host_DNS_name = $null; 
    }

    [void] setDNSName([String] $DNSName){
        $this.host_DNS_name = $DNSName; 
    }

    [String] getIP(){
        return $this.host_ip; 
    }

    [String] getDNSName(){
        return $this.host_DNS_name; 
    }

    [String] getMAC(){
        return $this.host_mac; 
    }

    [boolean] getIsSwitch(){
        return $this.host_is_switch; 
    }

    [void] WriteInfo(){
        Write-Host ("`n### HOST: {0} ###`n`tMAC:`t`t{1}`n`tIP:`t`t`t{2}`n`tIsSwitch:`t{3}" -f $this.getDNSName(), $this.getMAC(), $this.getIP(), $this.getIsSwitch());
    }

    [String] static macParse([String] $inMAC){
        [String]$swp = $inMAC.Trim().ToLower();  
        # разбираем mac-адрес вида "cc:3e:5f:e0:17:a9" или "cc-3e-5f-e0-17-a9" 
        if($swp -match '([0-9a-f]{2}[-:]?){6}'){
            return ($matches[0]) -replace '[-:]','' ; 
        }
        return $swp; 
    }
}


Class CSwitch{
    [CHost]  $switch_host;   
    [System.Collections.ArrayList]$switch_ports;
#    [System.Collections.ArrayList]$switch_ports = New-Object System.Collections.ArrayList($null); 

    CSwitch([CHost] $SwitchHost){
       $this.switch_host = $SwitchHost; 
       $SwitchHost.host_is_switch = $true;
       $SwitchHost.host_is_switch_link = $this;

       $this.switch_ports = New-Object System.Collections.ArrayList($null);  
    }
   
    [String] getDNSName(){
       return $this.switch_host.getDNSName(); 
    }

    [String] getMAC(){
       return $this.switch_host.getMAC(); 
    }

    [String] getIP(){
       return $this.switch_host.getIP(); 
    }

    [void] WriteInfo(){
        Write-Host ("`n### SWITCH: {0} ###`n`tMAC:`t`t{1}`n`tIP:`t`t`t{2}`n" -f $this.getDNSName(), $this.getMAC(), $this.getIP());
    }

    [void] addMACToPort([CHost]$MAC, [String] $LPort, [String] $PPort){
        # Если данный порт не существует еще на коммутаторе -- добавить его  
        $curPort = $this.switch_ports.Where({$_.getPortID() -like $LPort})[0]; 
        if($null -eq $curPort){
            $curPort = [CSwitchPort]::new($LPort, $PPort, $this);
            $this.switch_ports.Add($curPort); 
        }
        # добавляем mac-адрес хоста в таблицу mac-адресов порта
        $curPort.addMAC($MAC); 
    }

    [CSwitchPort] getPortWithHost([CHost] $CheckHost){
#        return $this.switch_ports.Where({$_.port_MACs.Where({$_.getMAC() -like $Host.getMAC()})[0]})[0];
        return $this.switch_ports.Where({$_.port_MACs.Where({$_ -eq $CheckHost})[0]-ne $null})[0];
    }

    [void] deleteMAC([CHost] $Private:Host) {
        foreach($cleaningPort in $this.getPortWithHost($Private:Host)){
            $cleaningPort.deleteMAC($Private:Host); 
        }
    }
}


$CDate = Get-Date -Format s; 

<#
    Заполяем таблицу SwitchesARP[MAC] = { mac=MAC, ip=IP, SwitchName=SWITCHNAME }, заполняем IP
#>
[System.Collections.ArrayList]$SW_POOL  = New-Object System.Collections.ArrayList($null); 
[System.Collections.ArrayList]$MAC_POOL = New-Object System.Collections.ArrayList($null); 

Import-Csv -Delimiter ';' -Path $SwitchListCSV | ForEach-Object {
    $SwitchHost = [CHost]::new($_.MAC, $_.IP, $true); 
    $SwitchHost.setDNSName($_.SwitchName)
    $MAC_POOL.Add($SwitchHost);
    $Switch = [CSwitch]::new($SwitchHost); 
    $SW_POOL.Add($Switch);
    Write-Debug "Add switch $($_.SwitchName)" ; 
}

<#
    По прямой dns-зоне строим словарь ip-адресов/имен-хостов 
#>
$dictDNS = Get-DnsServerResourceRecord -ComputerName v-brn-k30-dc01 -ZoneName 'tonarplus.local' | 
            where-object -property RecordType -like 'A' | 
            Select-Object -Property @{'n'='HostName'; 'e'={$_.HostName}} , 
                                    @{'n'='IP'; 'e'={$_.RecordData.IPv4Address.IPAddressToString}} ;

<#
    По ARP-таболице Mikrotik заполяем таблицу хостов 
#>
$curMAC = $null; 
$curIP  = $null; 
&$SNMP_UTIL walk $MainGW public .1.3.6.1.2.1.4.22.1.2 | ForEach {
    $inStr = $_.Trim(); 
#    Write-Host "Get: $inStr" ; 
    $curHost = $null; 

    # текущая строка содержит IP-адрес хоста? 
    if($inStr -match '^Variable\s+=\s+ip\.ipNetToMediaTable\.ipNetToMediaEntry\.ipNetToMediaPhysAddress\.\d+\.(\d+)\.(\d+)\.(\d+)\.(\d+)$'){
        # разбираем-собираем его на октеты (можно было втупую все октеты скопом забрать в одной группировке -- но 
        # это же не наш метод)
        $curIP = "{0}.{1}.{2}.{3}" -f $matches[1],
                                      $matches[2],
                                      $matches[3],
                                      $matches[4];  
        Write-Debug "Get IP: $curIP" ; 
    } else { 
        # текущая строка содержит MAC-адрес хоста? 
        if($inStr -match '^Value\s+=\s+String\s+<0x([a-fA-F0-9]+)><0x([a-fA-F0-9]+)><0x([a-fA-F0-9]+)><0x([a-fA-F0-9]+)><0x([a-fA-F0-9]+)><0x([a-fA-F0-9]+)>$'){
        $curMAC = "{0}{1}{2}{3}{4}{5}" -f $matches[1],
                                          $matches[2],
                                          $matches[3],
                                          $matches[4],
                                          $matches[5],
                                          $matches[6]; 
        Write-Debug "Get MAC: $curMAC" ; 
        }
    }

    if($curMAC -ne $null -and $curIP -ne $null) {
        # найдены и mac-адрес хоста и ip-адрес

        # добавить в пул mac-адресов найденный mac (если он там отсутствует)
        $curHost = $MAC_POOL.Where({$_.getMAC() -like $curMAC})[0]; 
        if($curHost -eq $null) {
            $curHost = [CHost]::new($curMAC, $curIP, $false); 
            $dictDNS.where({$_.ip -like $curHost.getIP()}).HostName ;
            $curHost.setDNSName( $dictDNS.where({$_.ip -like $curHost.getIP()}).HostName );
<# ##### NEED FOR SPEED #######
            try{
                $curHost.setDNSName([System.Net.DNS]::GetHostByAddress($curHost.getIP()).HostName.split('.')[0]);
            }catch{
            }
#> 

            $MAC_POOL.Add($curHost);
 #           Write-Host ("Added host : {0} / {1}" -f $curHost.getIP(), $curHost.getMAC()) ; 
        }

        # теперь будем искать новую пару mac/ip
        $curMAC = $null; 
        $curIP  = $null; 
    }
}

<#
    Строим в памяти "слепок сети" по известным коммутаторам 
#>
ForEach( $CurSwitch in $SW_POOL ) {
    # Строим карту портов коммутатора PortMAP[logical_port]=Phisycal_Port 

    # Строим список PhysicalPorts[IDX] = Phisycal_Port 
    $SwitchPhysicalPorts = @{};  
    $CurPhysicalPort = $null; 
    $CurIdx          = $null; 

    &$SNMP_UTIL walk $($CurSwitch.getIP()) public .1.2.840.10006.300.43.1.2.1.1.13 | ForEach {
        $inStr = $_; 
        if($inStr -match '^Variable\s+=\s+\.iso\.2\.840\.10006\.300\.43\.1\.2\.1\.1\.13\.(\d+)$'){
            $CurPhysicalPort = $matches[1]; 
        } else {
            if($inStr -match '^Value\s+=\s+Integer32\s+(\d+)$'){
                $CurIdx = $matches[1] ; 
            }
        }

        if($CurIdx -ne $null -and $CurPhysicalPort -ne $null){ # если пара Физический_порт-индекс заполнена
            if(([String]$CurIdx).ToInt16($null) -eq 0){ # если индекс 0 , то физический порт совпадет с логическим
                $SwitchPhysicalPorts[$CurPhysicalPort] = $CurPhysicalPort; 
            } else { # иначе логическому порту будут соответствовать несколько физических 
                $SwitchPhysicalPorts[$CurIdx] += " $CurPhysicalPort"; 
            }
            $CurPhysicalPort = $null; 
            $CurIdx          = $null; 
        }
    }

    # Строим список LogicalPorts[PortID] = Phisycal_Port 
    $SwitchLogicalPorts = @{};  
    $CurLogicalPort = $null; 
    $CurIdx         = $null; 
    &$SNMP_UTIL walk $($CurSwitch.getIP()) public .1.3.6.1.2.1.17.1.4.1.2 | ForEach {
        $inStr = $_; 
        if($inStr -match '^Variable\s+=\s+\.17\.1\.4\.1\.2\.(\d+)$'){
            $CurLogicalPort = $matches[1]; 
        } else {
            if($inStr -match '^Value\s+=\s+Integer32\s+(\d+)$'){
                $CurIdx = $matches[1] ; 
            }
        }

        if($CurIdx -ne $null -and $CurLogicalPort -ne $null){ # если пара логический_порт-индекс заполнена
            $SwitchLogicalPorts[$CurLogicalPort] = $(if($SwitchPhysicalPorts[$CurIdx] -ne $null){$SwitchPhysicalPorts[$CurIdx]}else{$CurLogicalPort});

            $CurLogicalPort = $null; 
            $CurIdx         = $null; 
        }
    }


    $curMAC = $null; 
    $curLPort = $null; 

    # interview all known switches 
<#
    ForEach( $TestSwitch in $SW_POOL ) {
        Write-Warning ("Test switch: {0}" -f $TestSwitch.switch_host.host_ip) ; 
        Test-NetConnection -Hops 2 -ComputerName $TestSwitch.switch_host.host_ip | Out-Null ; 
    }
#>    
    &$SNMP_UTIL walk $($CurSwitch.getIP()) public .1.3.6.1.2.1.17.7.1.2.2.1.2 | ForEach {
        $inStr = $_.Trim(); 
        $curHost = $null; 

        # текущая строка содержит MAC-адрес? 
        if($inStr -match '^Variable\s+=\s+\.17\.7\.1\.2\.2\.1\.2\.(\d+)\.(\d+)\.(\d+)\.(\d+)\.(\d+)\.(\d+)\.(\d+)$'){
            $curMAC = "{0:x2}{1:x2}{2:x2}{3:x2}{4:x2}{5:x2}" -f $matches[2].ToInt16($null),
                                                                $matches[3].ToInt16($null),
                                                                $matches[4].ToInt16($null),
                                                                $matches[5].ToInt16($null),
                                                                $matches[6].ToInt16($null),
                                                                $matches[7].ToInt16($null); 
        } else { 
            # текущая строка содержит номер логического порта ? 
            if($inStr -match '^Value\s+=\s+Integer32\s+(\d+)$'){
                $curLPort = $matches[1]; 
            }
        }
<#
        if($curMAC -like 'cc3e5f8909d7'){
            Write-Warning ("Catch {0} in switch {1} on port {2}" -f "cc3e5f8909d7", $curSwitch.switch_host.host_DNS_name, $curLPort) ; 
        }
#>
        if($curMAC -ne $null -and $curLPort -ne $null -and $curLPort -notlike "0") {
            # найдены и mac-адрес хоста и логический порт за которым этот mac виден на коммутаторе

            if($CurSwitch.getMAC() -notlike $curMAC){ # если это не собственный MAC-адрес коммутатора -- добавим в список адресов порта
                # добавить в пул mac-адресов найденный mac (если он там отсутствует)
                $curHost = $MAC_POOL.Where({$_.getMAC() -like $curMAC})[0]; 
                if($curHost -eq $null) {
                    $curHost = [CHost]::new($curMAC, $null, $false); 
                    $MAC_POOL.Add($curHost);
                }
                # Добавляем для текущего коммутатора CurSwitch в mac-таблицу порта curLPort mac-адрес curHost
                $curSwitch.addMACToPort($curHost, $curLPort, $SwitchLogicalPorts[$curLPort]); 
##                Write-Host ("add to switch {0} on port {1} address {2}" -f $curSwitch.getDNSName(), $curLPort, $curHost.getMAC()) ; 
            }
            # теперь будем искать новую пару mac/port
            $curMAC = $null; 
            $curLPort = $null; 
        }
    }
}

<#
 К этому моменту готова карта коммутаторов с портами и таблицей mac-адресов на них. 
#>

<#
    ищем/разбираем uplink-порты на коммутаторах: 
    Для каждого коммутатора swA перебираем порты: 
        Если portA в своей таблице адресов содержит mac-адрес, то 
            перебираем все остальные порты (КРОМЕ portA) на этом коммутаторе, 
            на каждом из них ДЛЯ ВСЕХ коммутаторов, подключенных через эти порты, 
            удаляем этот MAC из таблиц портов этих коммутаторов. 
#>
# подчищаем сначала не-коммутаторы 
foreach($CurSwitch in $SW_POOL){
    foreach($CurPort in $CurSwitch.switch_ports) {
        # собираем mac-и , которые за другими портами (не за CurPort)
        if(-not $CurPort.isUpLink) {

            foreach($AnotherSwitch in $SW_POOL.Where({ $_ -ne $CurSwitch }) ){
                foreach($CurMAC in $CurPort.port_MACs) {
                    $CleaningPort = $AnotherSwitch.getPortWithHost($CurMAC) ; 
                    if($null -ne $CleaningPort){
                        $CleaningPort.deleteMAC($curMAC); 
                    }
                }
            }
        }
    }
}

foreach($CurSwitch in $SW_POOL){
    foreach($CurPort in $CurSwitch.switch_ports) {
        # собираем mac-и , которые за другими портами (не за CurPort)
        if($CurPort.isUpLink) {
            $AnotherPortMACs = $CurSwitch.switch_ports.Where({ $_ -ne $CurPort }).port_MACs ; 
            # удаляем собранные mac-и из коммутаторов спрятанных за CurPort
            foreach($AnotherSwitch in $CurPort.getSwitchesBehindPort()){
                if($null -ne $AnotherSwitch){
                    foreach($curHost in $AnotherPortMACs){
                        if($null -ne $curHost) {
                            $CleaningPort = $AnotherSwitch.getPortWithHost($curHost) ; 
                            if($null -ne $CleaningPort){
                                $CleaningPort.deleteMAC($curHost); 
                            }
                        }
                    }
                }
            }
        }
    }
}

<#
# итоговая картина 
#>
$curHost | 
Select-Object -Property @{'n'='switch_name';   'e'={$null}},
                        @{'n'='switch_IP';     'e'={$null}},
                        @{'n'='switch_MAC';    'e'={$null}},
                        @{'n'='port';          'e'={$null}},
                        @{'n'='port_isUpLink'; 'e'={$null}},
                        @{'n'='host_name';     'e'={$null}},
                        @{'n'='host_IP';       'e'={$null}},
                        @{'n'='host_MAC';      'e'={$null}},
                        @{'n'='host_isSwitch'; 'e'={$null}} | 
Export-Csv -Delimiter ';' -Path $OutReport

foreach ($curSwitch in $SW_POOL.GetEnumerator()){
    foreach($curPort in ([CSwitch]$curSwitch).switch_ports){
        foreach($curHost in ([CSwitchPort]$curPort).port_MACs){
            $curHost| 
                Select-Object -Property @{'n'='switch_name';   'e'={([CSwitch]$curSwitch).getDNSName()}},
                                        @{'n'='switch_IP';     'e'={([CSwitch]$curSwitch).getIP()}}, 
                                        @{'n'='switch_MAC';    'e'={([CSwitch]$curSwitch).getMAC()}},
                                        @{'n'='port';          'e'={([CSwitchPort]$curPort).getPhysicalPort()}}, 
                                        @{'n'='port_isUpLink'; 'e'={([CSwitchPort]$curPort).getIsUpLink()}}, 
                                        @{'n'='host_name';     'e'={([CHost]$curHost).getDNSName()}},  
                                        @{'n'='host_IP';       'e'={([CHost]$curHost).getIP()}},  
                                        @{'n'='host_MAC';      'e'={([CHost]$curHost).getMAC()}},  
                                        @{'n'='host_isSwitch'; 'e'={([CHost]$curHost).getIsSwitch()}} | 
                Export-Csv -Delimiter ';' -Path $OutReport -Append
        }
    }
} ; 


<#
foreach ($curSwitch in $SW_POOL.GetEnumerator()){
   Write-Host ("{0}`nSwitch {1}" -f ('*'*40), $curSwitch.getDNSName()); 
   foreach($curPort in $curSwitch.switch_ports.GetEnumerator()){
     Write-Host ("{0}Port: {1}`n{0} {2}" -f 
            ("`t"*2), 
            $curPort.getPortID(), 
            $curPort.port_MACs.ForEach(
                { 
                    "{0}{1}{2}" -f 
                        $(if(([CHost]$_).getDNSName() -ne ""){"{0}/" -f ([CHost]$_).getDNSName()}else{""}),
                        $(if(([CHost]$_).getIP()      -ne ""){"{0}/" -f ([CHost]$_).getIP()}else{""}),   
                        ([CHost]$_).getMAC();
                }
            ) -join ','
     ); 
   }
}
#>