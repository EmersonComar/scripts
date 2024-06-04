#!/bin/bash

## Script criado para realizar a instalação básica
## do zabbix em um Debian 11

##### ideia para o futuro
show_spinner() {
  local pid=$1
  local mensagem=$2
  local delay=0.1
  local spinstr='|/-\'
  local temp

  while ps -p $pid > /dev/null 2>&1; do
    temp=${spinstr#?}
    printf "  [%c] %c" "$spinstr" "$mensagem"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b"
  done
}
####################


execute_step() {
    local log="/tmp/install_zabbix"
    local step_message=$1
    local command=$2

    echo -n "  [-] $step_message"
    bash -c "$command" >> $log &
    
    pid=$!

    if wait $pid; then
        echo -e "\r  [ok] $step_message"
    else
        echo -e "\r  [erro] $step_message"
        printf "Erro ao executar %s. Verifique o log em %s\n" "$step_message" "$log"
        exit 1
    fi
}

get_debian_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo $VERSION_ID
    else
        echo 0s
    fi
}

mensagem_boasvindas() {
    echo -e " _____   _    ____  ____ _____  __
|__  /  / \  | __ )| __ )_ _\ \/ /
  / /  / _ \ |  _ \|  _ \| | \  / 
 / /_ / ___ \| |_) | |_) | | /  \ 
/____/_/   \_\____/|____/___/_/\_\\
"
echo -e "Instalação automatizada\n"
}

validar_usuario() {
    echo -e "Validando usuário\n"
    if [ "$UID" -ne 0 ]; then
        echo "  [erro] Execute com permissões root"
        exit 1
    fi
    echo "  [ok] Permissões de root utilizadas"
}

step_1(){
    echo -e "\nPreparando preparando sistema (1/5)"
    execute_step "Atualizando repositórios (1/3)" "apt-get update -q"
    execute_step "Atualizando sistema (2/3)" "apt-get upgrade -yq"
    execute_step "Instalando dependências (3/3)" "apt-get install curl wget gzip gnupg2 net-tools locales-all -yq"
}

step_2() {
    echo -e "\nInstalando serviços (2/5)"
    execute_step "Baixando repositórios (1/6)" "wget -P /tmp https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb > /dev/null 2>&1"
    execute_step "Instalando repositório Zabbix (2/6)" "dpkg -i /tmp/zabbix-release_6.4-1+debian11_all.deb"
    execute_step "Atualizando repositórios do sistema (3/6)" "apt-get update -q"
    execute_step "Instalando serviços básicos (4/6)" "apt-get install zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent -yq"
    execute_step "Instalando NGINX (5/6)" "apt-get install nginx-full -yq"
    execute_step "Instalando MariaDB (6/6)" "apt-get install mariadb-server -yq"
}

step_3() {
    local SENHA_BANCO_ROOT=$1
    local SENHA_BANCO_ZABBIX=$2

    echo -e "\nConfigurações do Banco de dados (3/5)"

    local COMMAND="create database zabbix character set utf8mb4 collate utf8mb4_bin;"
    execute_step "Criando database (1/6)" "mysql -uroot -e \"$COMMAND\""

    local COMMAND="create user zabbix@localhost identified by '$SENHA_BANCO_ZABBIX';"
    execute_step "Criando usuário zabbix (2/6)" "mysql -uroot -e \"$COMMAND\""

    local COMMAND="grant all privileges on zabbix.* to zabbix@localhost;;"
    execute_step "Ajustando permissões do usuário zabbix (3/6)" "mysql -uroot -e \"$COMMAND\""

    local COMMAND="zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix --password=\"$SENHA_BANCO_ZABBIX\" zabbix"
    execute_step "Criando tabelas (4/6)" "$COMMAND"

    local COMMAND="ALTER USER 'root'@'localhost' IDENTIFIED BY '${SENHA_BANCO_ROOT}';"
    execute_step "Ajustando acesso root (5/6)" "mysql -uroot -e \"$COMMAND\""

    execute_step "Ajustando acesso ao database (6/6)" "sed -i 's/# DBPassword=/DBPassword=$SENHA_BANCO_ZABBIX/' /etc/zabbix/zabbix_server.conf"
}

step_4() {
    echo -e "\nConfigurações do acesso web (4/5)"

    execute_step "Removendo server block padrão do nginx (1/3)" "rm /etc/nginx/sites-enabled/default"
    execute_step "Ajustando porta padrão nginx (2/3)" "sed -i 's/#        listen          8080;/listen 80;/' /etc/zabbix/nginx.conf"
    execute_step "Ajustando server name (3/3)" "sed -i 's/#        server_name     example.com;/server_name localhost;/' /etc/zabbix/nginx.conf"

}

step_5() {
    echo -e "\nRestartando serviços (5/5)"
    execute_step "MariaDB (1/5)" "systemctl restart mysql"
    execute_step "zabbix-server (2/5)" "systemctl restart zabbix-server"
    execute_step "zabbix-agent (3/5)" "systemctl restart zabbix-agent"
    execute_step "nginx (4/5)" "systemctl restart nginx"
    execute_step "php7.4-fpm (5/5)" "systemctl restart php7.4-fpm"
    execute_step "Ajustando inicialização dos serviços no boot" "systemctl enable zabbix-server zabbix-agent nginx php7.4-fpm mysql > /dev/null 2>&1"

}

step_6() {
    local SENHA_BANCO_ROOT=$1
    local SENHA_BANCO_ZABBIX=$2
    echo -e " _____ ___ _   _    _    _     ___ _____   _    _   _ ____   ___       
|  ___|_ _| \ | |  / \  | |   |_ _|__  /  / \  | \ | |  _ \ / _ \      
| |_   | ||  \| | / _ \ | |    | |  / /  / _ \ |  \| | | | | | | |     
|  _|  | || |\  |/ ___ \| |___ | | / /_ / ___ \| |\  | |_| | |_| | _ _ 
|_|   |___|_| \_/_/   \_\_____|___/____/_/   \_\_| \_|____/ \___(_|_|_)"
    echo -e "\nInstalação finalizada.\n"
    echo -e "Acesse: http://$(hostname -I | cut -d " " -f1)/ para realizar a configuração web"
    echo -e "Guarde com cuidado as seguintes credencias:"
    echo -e "Senha banco root: $SENHA_BANCO_ROOT"
    echo -e "Senha banco zabbix: $SENHA_BANCO_ZABBIX"
    echo -e "Não ficarão armazenadas em nenhum local\n"
}

excutando() {
    local SENHA_BANCO_ROOT=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c 15)
    local SENHA_BANCO_ZABBIX=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c 15)
    mensagem_boasvindas
    validar_usuario
    step_1
    step_2
    step_3 $SENHA_BANCO_ROOT $SENHA_BANCO_ZABBIX
    step_4
    step_5
    step_6 $SENHA_BANCO_ROOT $SENHA_BANCO_ZABBIX
}

excutando