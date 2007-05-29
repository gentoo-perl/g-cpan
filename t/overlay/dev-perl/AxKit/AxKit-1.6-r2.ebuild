# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/dev-perl/AxKit/AxKit-1.6-r2.ebuild,v 1.22 2007/01/20 14:40:12 mcummings Exp $

inherit perl-module

DESCRIPTION="The Apache AxKit Perl Module"
SRC_URI="http://axkit.org/download/${P}.tar.gz"
HOMEPAGE="http://axkit.org/"

SLOT="0"
LICENSE="|| ( Artistic GPL-2 )"
KEYWORDS="x86 amd64 alpha sparc ~ppc"
IUSE=""

DEPEND=">=www-misc/libapreq-1.0
	>=dev-perl/Compress-Zlib-1.10
	>=dev-perl/Error-0.13
	>=dev-perl/libwww-perl-5.64-r1
	>=virtual/perl-Storable-1.0.7
	>=dev-perl/XML-XPath-1.04
	>=dev-perl/XML-LibXML-1.31
	>=dev-perl/XML-LibXSLT-1.31
	>=dev-perl/XML-Sablot-0.50
	>=virtual/perl-Digest-MD5-2.09
	<www-apache/mod_perl-1.99
	dev-lang/perl"
RDEPEND="${DEPEND}"

src_unpack() {
	unpack ${A}
	cd ${S}
	cp Makefile.PL Makefile.PL.orig
	sed -e "s:0\.31_03:0.31:" Makefile.PL.orig > Makefile.PL
}

src_install() {
	perl-module_src_install

	diropts -o nobody -g nogroup
	dodir /var/cache/axkit
	dodir /home/httpd/htdocs/xslt
	insinto /etc/apache
	doins ${FILESDIR}/httpd.axkit
}
