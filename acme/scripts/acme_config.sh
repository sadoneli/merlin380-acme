#!/bin/sh
source /koolshare/scripts/base.sh
eval `dbus export acme`
acme_root="/koolshare/acme"
LOGFILE="/tmp/acme_run.log"
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
mkdir -p /jffs/ssl

start_issue(){
	case "$acme_provider" in
	1)
		# ali_dns
		echo_date 使用阿里dns接口申请证书... >> $LOGFILE
		#export Ali_Key="$acme_ali_arg1"
		#export Ali_Secret="$acme_ali_arg2"
		sed -i '/Ali_Key/d' /koolshare/acme/account.conf
		sed -i '/Ali_Secret/d' /koolshare/acme/account.conf
		echo -e "Ali_Key='$acme_ali_arg1'\nAli_Secret='$acme_ali_arg2'" >> /koolshare/acme/account.conf
		dnsapi=dns_ali
		;;
	2)
		# dnspod
		echo_date 使用dnspod接口申请证书... >> $LOGFILE
		#export DP_Id="$acme_dp_arg1"
		#export DP_Key="$acme_dp_arg2"
		sed -i '/DP_Id/d' /koolshare/acme/account.conf
		sed -i '/DP_Key/d' /koolshare/acme/account.conf
		echo -e "DP_Id='$acme_dp_arg1'\nDP_Key='$acme_dp_arg2'" >> /koolshare/acme/account.conf
		dnsapi=dns_dp
		;;
	3)
		# cloudxns
		echo_date 使用cloudxns接口申请证书... >> $LOGFILE
		#export CX_Key="$acme_xns_arg1"
		#export CX_Secret="$acme_xns_arg2"
		sed -i '/CX_Key/d' /koolshare/acme/account.conf
		sed -i '/CX_Secret/d' /koolshare/acme/account.conf
		echo -e "CX_Key='$acme_xns_arg1'\nCX_Secret='$acme_xns_arg2'" >> /koolshare/acme/account.conf
		dnsapi=dns_cx
		;;
	esac
	sleep 1
	cd $acme_root
	./acme.sh --home "$acme_root" --issue --dns $dnsapi -d $acme_domain -d $acme_subdomain.$acme_domain
}

install_cert(){
	cd $acme_root
	./acme.sh --home "$acme_root" --installcert -d $acme_domain --keypath /jffs/ssl/key.pem --fullchainpath /jffs/ssl/cert.pem --reloadcmd "service restart_httpd"
}

force_renew(){
	$acme_root/acme.sh --cron --force --home $acme_root
}

del_all_cert(){
	cd $acme_root
	find . -name "fullchain.cer*"|sed 's/\/fullchain.cer//g'|xargs rm -rf
	rm -rf /jffs/ssl/*
}

add_cron(){
	sed -i '/acme/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	cru a acme_renew "47 * * * * $acme_root/acme.sh --cron --home $acme_root"
}

del_cron(){
	sed -i '/acme/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
}

check_md5(){
	md5sum_cer_jffs=$(md5sum /jffs/ssl/cert.pem | sed 's/ /\n/g'| sed -n 1p)
	md5sum_cer_acme=$(md5sum "$acme_domain/fullchain.cer" | sed 's/ /\n/g'| sed -n 1p)
	md5sum_key_jffs=$(md5sum /jffs/ssl/key.pem | sed 's/ /\n/g'| sed -n 1p)
	md5sum_key_acme=$(md5sum "$acme_domain/$acme_domain.key" | sed 's/ /\n/g'| sed -n 1p)	
}

check_cert(){
	SUB=`openssl x509 -text -in "$acme_domain"/fullchain.cer|grep -A 1 "Subject Alternative Name"|tail -n1|cut -d "," -f1|cut -d ":" -f2|cut -d "." -f1`
	EXPIRE=`openssl x509 -text -in "$acme_domain"/fullchain.cer|grep "Not After"|sed 's/Not After ://g'|sed 's/^[ \t]*//g'`
}

apply_now(){
	echo_date 开始为$acme_domain申请证书！ >> $LOGFILE
	echo_date 证书申请过程可能会持续3分钟，请不要关闭或刷新本网页！ >> $LOGFILE
	sleep 2
	start_issue >> $LOGFILE 2>&1
	if [ "$?" == "1" ];then
		echo_date 证书申请失败，请检查插件配置、域名等是否正确！！ >> $LOGFILE
		echo_date 清理相关残留并关闭插件！！ >> $LOGFILE
		rm -rf "$acme_domain" > /dev/null 2>&1
		rm -rf http.header > /dev/null 2>&1
		dbus set acme_enable="0"
	else
		echo_date 证书申请成功！>> $LOGFILE
		echo_date 添加证书更新定时任务！
		add_cron >> $LOGFILE
		echo_date 安装证书！ >> $LOGFILE
		echo_date 安装证书会重启路由器web服务，安装完成后需要重新登录路由器 >> $LOGFILE
		echo_date 安装中，，，请等待页面自动刷新！ >> $LOGFILE
		echo XU6J03M7 >> $LOGFILE
		install_cert
	fi
}

case $1 in
start)
	# start by init
	if [ "$acme_enable" == "1" ];then
		# detect domain folder first
		cd $acme_root
		if [ -d "$acme_domain" ] && [ -f "$acme_domain/$acme_domain.key" ] && [ -f "$acme_domain/fullchain.cer" ];then
			check_md5
			if [ "$md5sum_cer_jffs"x = "$md5sum_cer_acme"x ] && [ "$md5sum_key_jffs"x = "$md5sum_key_acme"x ];then
				logger "检测到Let's Encrypt插件开启，且证书安装正确，添加证书更新定时任务"
				add_cron
			else
				logger "检测到Let's Encrypt插件开启，但是证书未正确安装！"
				logger "安装证书并添加证书更新定时任务！"
				install_cert
				add_cron
			fi
		else
			logger "$acme_domain证书未生成或者生成的证书有问题，清理相关残留并关闭插件！"
			rm -rf "$acme_domain" > /dev/null 2>&1
			rm -rf http.header > /dev/null 2>&1
			dbus set acme_enable="0"
		fi
	else
		logger "Let's Encrypt插件未开启，跳过！"
	fi
	;;
*)
	echo "------------------------------ Let's Encrypt merlin addon by sadog -------------------------------" > $LOGFILE
	echo "" >> $LOGFILE
	[ ! -L "/koolshare/init.d/S99acme.sh" ] && ln -sf /koolshare/scripts/acme_config.sh /koolshare/init.d/S99acme.sh
	if [ "$acme_action" == "1" ];then
	#提交按钮
		if [ "$acme_enable" == "1" ];then
			# detect domain folder and coresponding cert first
			cd $acme_root
			# 检测对应主域名证书是否申请过
			if [ -d "$acme_domain" ] && [ -f "$acme_domain/$acme_domain.key" ] && [ -f "$acme_domain/fullchain.cer" ];then
				# 申请过了，检测对应二级域名是否申请过了
				check_cert
				if [ "$acme_subdomain" == "$SUB" ];then
					# 对应你个二级域名申请过了，检测是否安装了
					check_md5
					if [ "$md5sum_cer_jffs"x = "$md5sum_cer_acme"x ] && [ "$md5sum_key_jffs"x = "$md5sum_key_acme"x ];then
						#安装了，检测定时任务
						echo_date 检测到已经为【$acme_subdomain.$acme_domain，$acme_domain】申请了证书并且正确安装，跳过！>> $LOGFILE
						cronjob=`cru l | grep acme_renew`
						if [ "$cronjob" ];then
							#有定时任务
							echo_date 检测到【$acme_subdomain.$acme_domain，$acme_domain】证书自动更新定时任务正常，跳过！>> $LOGFILE
						else
							#无定时任务
							echo_date 检测到【$acme_subdomain.$acme_domain，$acme_domain】证书自动更新定时任务未添加！>> $LOGFILE
							echo_date 添加证书更新定时任务！！>> $LOGFILE
							add_cron >> $LOGFILE
						fi
					else
						#申请过了，但是没有安装
						echo_date 检测到你之前生成【$acme_subdomain.$acme_domain，$acme_domain】的证书，本次跳过申请，直接安装！ >> $LOGFILE
						echo_date 如果该证书已经过期，请本次提交完成后手动更新证书。 >> $LOGFILE
						echo_date 添加证书更新定时任务！！>> $LOGFILE
						add_cron >> $LOGFILE
						echo_date 安装证书！ >> $LOGFILE
						echo_date 安装证书会重启路由器web服务，安装完成后需要重新登录路由器 >> $LOGFILE
						echo_date 安装中，，，请等待页面自动刷新！ >> $LOGFILE
						echo XU6J03M7 >> $LOGFILE
						install_cert
					fi
				else
					# 对应你个二级域名没申请过
					# 删除主域名文件夹并申请更新的
					echo_date 检测到你之前生成过该域名【$SUB.$acme_domain，$acme_domain】证书，但是本次申请的二级域名不同！ >> $LOGFILE
					echo_date 删除原先生成的证书，重新申请新的证书！ >> $LOGFILE
					rm -rf "$acme_domain"
					apply_now
				fi
			else
				#主域名文件夹不存在或者存在但是证书不齐全
				rm -rf "$acme_domain"
				apply_now			
			fi
		else
			if [ -d "$acme_domain" ] && [ -f "$acme_domain/$acme_domain.key" ] && [ -f "$acme_domain/fullchain.cer" ];then
				check_md5
				if [ "$md5sum_cer_jffs"x = "$md5sum_cer_acme"x ] && [ "$md5sum_key_jffs"x = "$md5sum_key_acme"x ];then
					echo_date 检测到你已经成功申请并安装证书，关闭插件仅仅会关闭证书的自动更新。>> $LOGFILE
					echo_date 关闭插件状态下仍然可以使用手动更新对证书进行更新，请注意你的证书的过期时间！>> $LOGFILE
				else
					echo_date 关闭插件 >> $LOGFILE
					del_cron
				fi
			else
				echo_date 关闭插件 >> $LOGFILE
				del_cron
			fi
		fi
	elif [ "$acme_action" == "2" ];then
		#强制更新
		echo_date 强制更新证书，即使证书未过期，请注意使用频率。>> $LOGFILE
		force_renew >> $LOGFILE
	elif [ "$acme_action" == "3" ];then
		#删除证书
		echo_date 删除所有本插件生成的证书...>> $LOGFILE
		echo_date 路由器上已经安装的证书...>> $LOGFILE
		del_all_cert
		echo_date 定时更新任务...>> $LOGFILE
		del_cron
		echo_date 关闭本插件！>> $LOGFILE
		dbus set acme_enbale="0"
	fi
	echo "" >> $LOGFILE
	echo XU6J03M6 >> $LOGFILE
	dbus remove acme_action
	;;
esac
