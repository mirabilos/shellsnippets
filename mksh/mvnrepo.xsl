<?xml version="1.0" encoding="UTF-8"?>
<!--
	This XSLT 1.0 file, converting XML to an XPath string list, is:
	Copyright © 2018 mirabilos <t.glaser@tarent.de>
	Licensor: tarent solutions GmbH, Bonn

	This is a derivative work of an original Work retrieved from the
	StackOverflow/StackExchange network, whose Original Author is:
	© 2011 Dimitre Novatchev <https://stackoverflow.com/users/36305>
	Source: https://stackoverflow.com/a/4747858/2171120
	Question by ant <https://stackoverflow.com/users/169277>

	Further incorporated works from the same site are by:

	© 2014 Sam Harwell <https://stackoverflow.com/users/138304>
	Source: https://stackoverflow.com/a/24831920/2171120
	Question by Mithil <https://stackoverflow.com/users/34219>

	© 2011 Mads Hansen <https://stackoverflow.com/users/14419>
	Source: https://stackoverflow.com/a/7523245/2171120
	Question by Paul <https://stackoverflow.com/users/925899>

	This Adaption may be Distributed or Publicly Performed under the
	CC-BY-SA 3.0 (unported) licence or (at Your option) any later
	version of that licence, as published by Creative Commons, with
	no associated URI or title of the Work supplied. Licence URI:
	https://creativecommons.org/licenses/by-sa/3.0/legalcode.txt
-->
<!DOCTYPE xsl:stylesheet [
<!ENTITY nl "&#x0A;">
]>
<!-- https://stackoverflow.com/a/4747858/2171120 -->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
	<xsl:output method="text" encoding="UTF-8" indent="no"/>
	<xsl:strip-space elements="*"/>
	<xsl:variable name="sq">'</xsl:variable>
	<xsl:template name="quote">
		<xsl:param name="str"/>
		<xsl:choose>
			<xsl:when test="contains($str, $sq)">
				<xsl:value-of select="substring-before($str, $sq)"/>
				<xsl:text>'\''</xsl:text>
				<xsl:call-template name="quote">
					<xsl:with-param name="str" select="substring-after($str, $sq)"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<xsl:value-of select="$str"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="renderEQvalue">
		<xsl:text>='</xsl:text>
		<xsl:call-template name="quote">
			<xsl:with-param name="str" select="."/>
		</xsl:call-template>
	</xsl:template>
	<xsl:template match="*[@* or not(*)]">
		<xsl:if test="not(*)">
			<xsl:text>/</xsl:text>
			<xsl:apply-templates select="ancestor-or-self::*" mode="path"/>
			<xsl:call-template name="renderEQvalue"/>
			<xsl:text>'&nl;</xsl:text>
		</xsl:if>
		<xsl:apply-templates select="@*|*"/>
	</xsl:template>
	<xsl:template match="*" mode="path">
		<xsl:value-of select="concat('/', name())"/>
		<xsl:variable name="precSiblings" select="count(preceding-sibling::*[name()=name(current())])"/>
		<xsl:variable name="nextSiblings" select="count(following-sibling::*[name()=name(current())])"/>
		<xsl:if test="$precSiblings or $nextSiblings">
			<xsl:value-of select="concat('[', $precSiblings + 1, ']')"/>
		</xsl:if>
	</xsl:template>
	<xsl:template match="@*">
		<xsl:text>/</xsl:text>
		<xsl:apply-templates select="../ancestor-or-self::*" mode="path"/>
		<xsl:text>[@</xsl:text>
		<xsl:value-of select="name()"/>
		<xsl:call-template name="renderEQvalue"/>
		<xsl:text>']&nl;</xsl:text>
	</xsl:template>
</xsl:stylesheet>
