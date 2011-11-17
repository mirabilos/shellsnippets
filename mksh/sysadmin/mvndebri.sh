#!/bin/mksh
rcsid='$MirOS: contrib/hosted/tg/deb/mkdebidx.sh,v 1.51 2011/05/13 20:53:29 tg Exp $'
rcsid='$Id: mvndebri.sh 2503 2011-11-17 15:28:58Z tglase $'
#-
# Copyright (c) 2008, 2009, 2010, 2011
#	Thorsten Glaser <tg@mirbsd.org>
# Copyright (c) 2011
#	Thorsten Glaser <t.glaser@tarent.de>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un-
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided "AS IS" and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person's immediate fault when using the work as intended.

if [[ $1 != /* || -z $2 || ! -d $1/$2/. ]]; then
	print -u2 Syntax error.
	exit 1
fi
jobname=$2

hn=$(hostname)
case $hn {
(hudson.evolvis.org)
	hn=evolvis-hudson
	repo_keyid=0x16B5D1B2
	;;
(dev-hudson?(.*))
	hn=dev-hudson
	repo_keyid=0x199D2F3B
	;;
(test-hudson?(.*))
	hn=test-hudson
	repo_keyid=0xDB58AF73
	;;
# […]
(tglase.bonn.tarent.de)
	hn=devel-testsystem
	repo_keyid=0x5EB8D3B3
	;;
(*)
	print -u2 "Cannot determine hostname from '$hn'"
	exit 1
	;;
}
case $hn {
(evolvis-hudson)
	dhn=jenkins-debs.evolvis.org
	;;
(*)
	dhn=${hn}-debs.bonn.tarent.de
	;;
}
repo_origin='tarent solutions GmbH'
repo_label=tarent_auto_${hn}_$jobname
repo_title="tarent $hn $jobname automatic DEB Repository"
function repo_description {
	typeset suite_nick=$1

	print -nr -- "tarent-$hn $jobname/$suite_nick autobuild repository"
}


#set -A dpkgarchs -- alpha amd64 arm armeb armel armhf avr32 hppa \
#    i386 ia64 kfreebsd-amd64 kfreebsd-i386 lpia m32r m68k mips mipsel \
#    powerpc powerpcspe ppc64 s390 s390x sh3 sh3eb sh4 sh4eb sparc
set -A dpkgarchs -- amd64 i386

function putfile {
	tee $1 | gzip -n9 >$1.gz
}

function sortlist {
	typeset x u=$1

	if [[ $u = -u ]]; then
		shift
	else
		u=
	fi

	for x in "$@"; do
		print -r -- "$x"
	done | sort $u
}

set +U
export LC_ALL=C
unset LANGUAGE
saveIFS=$IFS
cd "$1/$2"
shift
shift
if [[ ! -d dists/. ]]; then
	print -u2 Not an APT repository.
	exit 1
fi

suites=:
for suite in "$@"; do
	suites=:dists/$suite$suites
done

allsuites=
for suite in dists/*; do
	allsuites="$allsuites${allsuites:+ }${suite##*/}"
	[[ $suites = : || $suites = *:"$suite":* ]] || continue
	components=Components:
	for dist in $suite/*; do
		[[ -d $dist/. ]] || continue
		rm -rf $dist/binary-* $dist/source
		ovf= oef= osf=
		[[ -s $dist/override.file ]] && ovf=$dist/override.file
		[[ -s $dist/override.extra ]] && oef="-e $dist/override.extra"
		[[ -s $dist/override.src ]] && osf="-s $dist/override.src"
		components="$components ${dist##*/}"
		for arch in ${dpkgarchs[*]} all; do
				print "\n===> Creating" \
				    "${dist#dists/}/$arch/Packages\n"
				mkdir -p $dist/binary-$arch
				dpkg-scanpackages $oef -m -a $arch \
				    $dist $ovf | \
				    putfile $dist/binary-$arch/Packages
		done
		print "\n===> Creating ${dist#dists/}/Sources"
		mkdir -p $dist/source
		dpkg-scansources $osf \
		    $dist $ovf | \
		    putfile $dist/source/Sources
		print done.
	done
	print "\n===> Creating ${suite#dists/}/Release.gpg"
	rm -f $suite/Release*
	(cat <<-EOF
		Origin: ${repo_origin}
		Label: ${repo_label}
		Suite: ${suite##*/}
		Codename: ${suite##*/}
		Date: $(date -u)
		Architectures: all ${dpkgarchs[*]} source
		$components
		Description: $(repo_description "${suite##*/}")
		MD5Sum:
	EOF
	exec 4>$suite/Release-sha1
	exec 5>$suite/Release-sha2
	print -u4 SHA1:
	print -u5 SHA256:
	cd $suite
	for n in Contents-* */{binary-*,source}/{Packag,Sourc}es*; do
		[[ -f $n ]] || continue
		# GNU *sum tools are horridly inefficient
		set -A x -- $(md5sum "$n")
		nm=${x[0]}
		set -A x -- $(sha1sum "$n")
		nsha1=${x[0]}
		set -A x -- $(sha256sum "$n")
		nsha2=${x[0]}
		ns=$(stat -c '%s' "$n")
		print " $nm $ns $n"
		print -u4 " $nsha1 $ns $n"
		print -u5 " $nsha2 $ns $n"
	done) >$suite/Release
	cat $suite/Release-sha1 $suite/Release-sha2 >>$suite/Release
	rm $suite/Release-sha1 $suite/Release-sha2
	gpg -u $repo_keyid -sb --batch \
	    --passphrase-file /etc/tarent/maven.kpw \
	    <$suite/Release >$suite/Release.gpg
done

print "\n===> Creating debidx.htm\n"

integer nsrc=0 nbin=0
br='<br />'

for suite in dists/*; do
	for dist in $suite/*; do
		[[ -d $dist/. ]] || continue
		suitename=${suite##*/}
		if [[ $suitename != +([a-z0-9_]) ]]; then
			print -u2 "Invalid suite name '$suitename'"
			continue 2
		fi
		distname=${dist##*/}
		if [[ $distname != +([a-z0-9_-]) ]]; then
			print -u2 "Invalid dist name '$distname'"
			continue
		fi

		gzip -dc $dist/source/Sources.gz |&
		pn=; pv=; pd=; pp=; Lf=
		while IFS= read -pr line; do
			case $line {
			(" "*)
				if [[ -n $Lf ]]; then
					eval x=\$$Lf
					x=$x$line
					eval $Lf=\$x
				fi
				;;
			("Package: "*)
				pn=${line##Package:*([	 ])}
				Lf=pn
				;;
			("Version: "*)
				pv=${line##Version:*([	 ])}
				Lf=pv
				;;
			("Binary: "*)
				pd=${line##Binary:*([	 ])}
				Lf=pd
				;;
			("Directory: "*)
				pp=${line##Directory:*([	 ])}
				Lf=pp
				;;
			(?*)	# anything else
				Lf=
				;;
			(*)	# empty line
				if [[ -n $pn && -n $pv && -n $pd && -n $pp ]]; then
					i=0
					while (( i < nsrc )); do
						[[ ${sp_name[i]} = "$pn" && \
						    ${sp_dist[i]} = "$distname" ]] && break
						let i++
					done
					if (( i == nsrc )); then
						let nsrc++
						pvo=
						ppo=
					else
						eval pvo=\$\{sp_ver_${suitename}[i]\}
						eval ppo=\$\{sp_dir_${suitename}[i]\}
					fi
					sp_name[i]=$pn
					sp_dist[i]=$distname
					#sp_suites[i]="${sp_suites[i]} $suitename"
					eval sp_ver_${suitename}[i]='${pvo:+$pvo,}$pv'
					eval sp_dir_${suitename}[i]='${ppo:+$ppo,}$pp/'
					sp_desc[i]=${sp_desc[i]},$pd
				fi
				pn=; pv=; pd=; pp=; Lf=
				;;
			}
		done

		gzip -dc $(for f in $dist/binary-*/Packages.gz; do
			[[ -e $f ]] || continue
			realpath "$f"
		done | sort -u) |&
		pn=; pv=; pd=; pp=; pN=; pf=; Lf=
		while IFS= read -pr line; do
			case $line {
			(" "*)
				if [[ -n $Lf ]]; then
					eval x=\$$Lf
					x=$x$line
					eval $Lf=\$x
				fi
				;;
			("Package: "*)
				pN=${line##Package:*([	 ])}
				Lf=pN
				;;
			("Source: "*)
				pn=${line##Source:*([	 ])}
				pn=${pn%% *}
				Lf=pn
				;;
			("Version: "*)
				pv=${line##Version:*([	 ])}
				Lf=pv
				;;
			("Description: "*)
				pd=${line##Description:*([	 ])}
				;;
			("Architecture: "*)
				pp=${line##Architecture:*([	 ])}
				Lf=pp
				;;
			("Filename: "*)
				pf=${line##Filename:*([	 ])}
				Lf=pf
				;;
			(?*)	# anything else
				Lf=
				;;
			(*)	# empty line
				if [[ $pf = *:* || $pf = *'%'* ]]; then
					print -u2 Illegal character in $dist \
					    packages $pp "'Filename: $pf'"
					exit 1
				fi
				[[ -n $pn ]] || pn=$pN
				if [[ -n $pn && -n $pv && -n $pd && -n $pp ]]; then
					i=0
					while (( i < nbin )); do
						[[ ${bp_disp[i]} = "$pN" && ${bp_desc[i]} = "$pd" && \
						    ${bp_dist[i]} = "$distname" ]] && break
						let i++
					done
					(( i == nbin )) && let nbin++
					bp_name[i]=$pn
					bp_disp[i]=$pN
					bp_dist[i]=$distname
					#bp_suites[i]="${bp_suites[i]} $suitename"
					[[ -n $pf ]] && pv="<a href=\"$pf\">$pv</a>"
					pv="$pp: $pv"
					eval x=\${bp_ver_${suitename}[i]}
					[[ $br$x$br = *"$br$pv$br"* ]] || x=$x${x:+$br}$pv
					eval bp_ver_${suitename}[i]=\$x
					bp_desc[i]=$pd
				fi
				pn=; pv=; pd=; pp=; pN=; pf=; Lf=
				;;
			}
		done
	done
done

(cat <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
 "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en"><head>
 <meta http-equiv="content-type" content="text/html; charset=utf-8" />
 <meta name="MSSmartTagsPreventParsing" content="TRUE" />
EOF
print -r -- " <title>${repo_title} Index</title>"
cat <<'EOF'
 <meta name="generator" content="$Id: mvndebri.sh 2503 2011-11-17 15:28:58Z tglase $ based on $MirOS: contrib/hosted/tg/deb/mkdebidx.sh,v 1.51 2011/05/13 20:53:29 tg Exp $" />
 <style type="text/css">
  table {
   border: 1px solid black;
   border-collapse: collapse;
   text-align: left;
   vertical-align: top;
  }
  tr {
   border: 1px solid black;
   text-align: left;
   vertical-align: top;
  }
  td {
   border: 1px solid black;
   text-align: left;
   vertical-align: top;
  }
  th {
   background-color: #000000;
   color: #FFFFFF;
  }
  .tableheadcell {
   border: 1px solid #999999;
   padding: 3px;
   white-space: nowrap;
  }
  .srcpkgline {
   background-color: #CCCCCC;
  }
  .srcpkgdist {
   background-color: #666666;
   color: #FFFFFF;
   font-weight: bold;
  }
  .binpkgdist {
   background-color: #999999;
   color: #FFFFFF;
   font-weight: bold;
  }
 </style>
</head><body>
EOF
print -r -- "<h1>${repo_title}</h1>"
cat <<EOF
<p><a href="dists/">Browse</a> the repository.
 This repository uses <a
  href="http://pgp.uni-mainz.de:11371/pks/lookup?search=${repo_keyid}&amp;op=vindex">${repo_keyid}</a>
 as signing key.
</p>
<h2>Suites</h2>
<ul>
EOF

allsuites=$(for suitename in $allsuites; do
	print $suitename
done | sort -u)

for suitename in $allsuites; do
	suite=dists/$suitename
	print -n " <li>${suite##*/}: <a href=\"$suite/\">$jobname for $suitename</a> (dists:"
	vdists=
	for dist in $suite/*; do
		[[ -d $dist/. ]] || continue
		distname=${dist##*/}
		vdists="$vdists $distname"
		print -n " <a href=\"$suite/$distname/\">$distname</a>"
	done
	print ")<br />"
	print " <tt>deb http://${dhn}/$jobname $suitename$vdists</tt>"
	print "</li>"
done
print "</ul>"
print "<h2>Packages</h2>"
print "<table width=\"100%\"><thead>"
print "<tr class=\"tablehead\">"
print " <th class=\"tableheadcell\">dist</th>"
print " <th class=\"tableheadcell\" rowspan=\"2\">Binary / Description</th>"
for suitename in $allsuites; do
	print " <th class=\"tableheadcell\" rowspan=\"2\">$suitename</th>"
done
print "</tr><tr class=\"tablehead\">"
print " <th class=\"tableheadcell\">package name</th>"
print "</tr></thead><tbody>"

set -A bp_sort
i=0
while (( i < nbin )); do
	print $i ${bp_disp[i++]} #${bp_suites[i]}
done | sort -k2 |&
while read -p num rest; do
	bp_sort[${#bp_sort[*]}]=$num
done

i=0
while (( i < nsrc )); do
	print $i ${sp_name[i++]}
done | sort -k2 |&
while read -p num rest; do
	print "\n<!-- sp #$num = ${sp_name[num]} -->"
	print "<tr class=\"srcpkgline\">"
	print " <td class=\"srcpkgdist\">${sp_dist[num]}</td>"
	pd=
	for x in $(tr ', ' '\n' <<<"${sp_desc[num]}" | sort -u); do
		[[ -n $x ]] && pd="$pd, $x"
	done
	print " <td rowspan=\"2\" class=\"srcpkgdesc\">${pd#, }</td>"
	for suitename in $allsuites; do
		eval pvo=\${sp_ver_${suitename}[num]}
		eval ppo=\${sp_dir_${suitename}[num]}
		IFS=,
		set -A pva -- $pvo
		set -A ppa -- $ppo
		IFS=$saveIFS
		(( ${#pva[*]} )) || pva[0]=
		y=
		i=0
		while (( i < ${#pva[*]} )); do
			pv=${pva[i]}
			pp=${ppa[i]}
			if [[ $pv = *""* ]]; then
				pvdsc=${pv%%""*}
				pv=${pv##*""}
			else
				pvdsc=$pv
			fi
			if [[ -z $pv ]]; then
				pv=-
			elif [[ $pp != ?(/) ]]; then
				pv="<a href=\"$pp${sp_name[num]}_${pvdsc##+([0-9]):}.dsc\">$pv</a>"
			fi
			[[ $pp != ?(/) ]] && pv="<a href=\"$pp\">[dir]</a> $pv"
			y=${y:+"$y<br />"}$pv
			let i++
		done
		print " <td rowspan=\"2\" class=\"srcpkgitem\">$y</td>"
	done
	print "</tr><tr class=\"srcpkgline\">"
	print " <td class=\"srcpkgname\">${sp_name[num]}</td>"
	print "</tr>"
	k=0
	while (( k < nbin )); do
		(( (i = bp_sort[k++]) < 0 )) && continue
		[[ ${bp_name[i]} = "${sp_name[num]}" && \
		    ${bp_dist[i]} = "${sp_dist[num]}" ]] || continue
		bp_sort[k - 1]=-1
		#print "<!-- bp #$i for${bp_suites[i]} -->"
		print "<!-- bp #$i -->"
		print "<tr class=\"binpkgline\">"
		print " <td class=\"binpkgname\">${bp_disp[i]}</td>"
		print " <td class=\"binpkgdesc\">${bp_desc[i]}</td>"
		for suitename in $allsuites; do
			eval pv=\${bp_ver_${suitename}[i]}
			if [[ -z $pv ]]; then
				pv=-
			fi
			print " <td class=\"binpkgitem\">$pv</td>"
		done
		print "</tr>"
	done
done

num=0
for i in ${bp_sort[*]}; do
	(( i < 0 )) && continue
	if (( !num )); then
		print "\n<!-- sp ENOENT -->"
		print "<tr class=\"srcpkgline\">"
		print " <td class=\"srcpkgname\">~ENOENT~</td>"
		print " <td class=\"srcpkgdesc\">binary" \
		    "packages without a matching source package</td>"
		for suitename in $allsuites; do
			print " <td class=\"srcpkgitem\">-</td>"
		done
		print "</tr>"
		num=1
	fi
	#print "<!-- bp #$i for${bp_suites[i]} -->"
	print "<!-- bp #$i -->"
	print "<tr class=\"binpkgline\">"
	print " <td class=\"binpkgdist\">${bp_dist[i]}</td>"
	print " <td rowspan=\"2\" class=\"binpkgdesc\">${bp_desc[i]}</td>"
	for suitename in $allsuites; do
		eval pv=\${bp_ver_${suitename}[i]}
		if [[ -z $pv ]]; then
			pv=-
		fi
		print " <td rowspan=\"2\" class=\"binpkgitem\">$pv</td>"
	done
	print "</tr><tr class=\"binpkgline\">"
	print " <td class=\"binpkgname\">${bp_disp[i]}</td>"
	print "</tr>"
done

cat <<EOF

</tbody></table>

<p>• <a href="http://validator.w3.org/check/referer">Valid XHTML/1.1!</a>
 • <small>Generated on $(date -u +'%F %T') by <tt
 style="white-space:pre;">$rcsid</tt></small> •</p>
</body></html>
EOF

:) >debidx.htm
print done.
