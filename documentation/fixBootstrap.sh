#!/bin/bash
search="@import url(\"\/\/fonts.googleapis.com\/css?family=Roboto:400,500\");"
replace="@import url(\"..\/..\/roboto.css\\\");"
sed -i "s/${search}/${replace}/g" _build/html/_static/bootswatch-3.3.4/sandstone/bootstrap.min.css
search="navbar-brand{float:left;padding:20px 15px"
replace="navbar-brand{float:left;padding:8px 15px"
sed -i "s/${search}/${replace}/g" _build/html/_static/bootswatch-3.3.4/sandstone/bootstrap.min.css