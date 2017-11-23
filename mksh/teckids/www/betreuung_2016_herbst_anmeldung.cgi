#!/bin/mksh
# -*- mode: sh -*-

conf=betreuung_2016_herbst
kurz=BHerbst16
lang="Ferienbetreuung Herbst 2016"

set -A pflichtfeld   1      1       1        1            1              1               1                1             1         1        1      0      0      0      0      0      1     1            1             0     0           1         1
set -A fieldnames -- FormID Vorname Nachname Geburtsdatum Vorname_Eltern Nachname_Eltern Anschrift_Eltern PLZOrt_Eltern Schulname Schulort Klasse Tag_Mo Tag_Di Tag_Mi Tag_Do Tag_Fr eMail Eltern_eMail Kontaktumfang Kanal Bemerkungen OK_Eltern OK_Datenschutz

. "$(dirname "$0")/webform.sh"

mail_extra="Mein Kind hat das Anmeldeformular gemeinsam mit mir ausgefüllt und ich bin
mit der Teilnahme einverstanden. Darüberhinaus erkläre ich mich einverstanden, den
Teilnehmerbeitrag vor Ort zu begleichen."

automail_and_out
