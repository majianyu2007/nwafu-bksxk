var pageNumber = 0;   

// 侧边框点击事件
function initAsideDate(type, event) {
    if (type == 'user') {
        // 初始化学生信息
        $('#cvUnsuccessfulCourse').html('');
        initStudentInformation();
        CVDialog.unScroll();
        $('#cvAside').addClass('cv-expand');
    } else if (type == 'volunteer') {
        if (!selectVolunteerIsOpen) {
            // 打开选课结果页面（志愿模式和抢课模式跳转不同的页面）
        	var xgxkTitle = '公选课（已选）';
        	var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
        	if(sysParam.xgxkQueryTitle){
        		xgxkTitle = sysParam.xgxkQueryTitle + '（已选）';
            }
            var html = '<div class="xsxk-xktx-tab" style="max-height: 526px;">' +
	                '<ul>' +
	                    '<li>方案课程（已选）</li>' +
	                    '<li>' + xgxkTitle + '</li>' +
	                    '<li>退选日志</li>';
        	if(sysParam.useList == '1'){
        		html += '<li>队列信息</li>';
        	}
        	html += '</ul>' +
	                '<div class="xsxk-xktx-tab-content-0 bh-mt-8"><div class="courses"></div></div>' +
	                '<div class="xsxk-xktx-tab-content-1 bh-mt-8"><div class="courses"></div></div>' +
	                '<div class="xsxk-xktx-tab-content-2 bh-mt-8"><div class="courses"></div></div>';
        	if(sysParam.useList == '1'){
        		html += '<div class="xsxk-xktx-tab-content-3 bh-mt-8"><div class="courses"></div></div>';
        	}
        	html += '</div>';
        	var clientWidth = document.documentElement.clientWidth - 150;
        	if(clientWidth < 1000){
            	clientWidth = 1000;
            }
            var clientHeight = document.documentElement.clientHeight - 200;
            if(clientHeight < 550){
            	clientHeight = 550;
            }
            BH_UTILS.bhWindow(html, '',[], {
                width: clientWidth,
                maxWidth: clientWidth,
                height: clientHeight,
                close:function(){
                    // 查询已选志愿数量
                    querySelectVolunteerNum();
                    $(window).scrollTop(0);
                    reloadCourseList();
                    selectVolunteerIsOpen = false;
                }
            });
            $('.xsxk-xktx-tab .courses').height(clientHeight - 145);
            initTabs(type);
            CVDialog.restoreScroll();
            $('#cvAside').removeClass('cv-expand');
            event.stopPropagation();
            selectVolunteerIsOpen = true;
        }
    } else if (type == 'grablessons') {
        if (!selectCourseIsOpen) {
            // 正选模式
        	var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
            var html = '<div class="xsxk-xktx-tab" style="max-height: 526px;">' +
	                '<ul>' +
	                    '<li>已选课程</li>' +
	                    '<li>退选日志</li>';
            if(sysParam.useList == '1'){
        		html += '<li>队列信息</li>';
        	}
            html += '</ul>' +
                '<div class="xsxk-xktx-tab-content-0 bh-mt-8"><div class="courses"></div></div>' +
                '<div class="xsxk-xktx-tab-content-1 bh-mt-8"><div class="courses"></div></div>';
            if(sysParam.useList == '1'){
        		html += '<div class="xsxk-xktx-tab-content-2 bh-mt-8"><div class="courses"></div></div>';
        	}
            html += '</div>';
            var clientWidth = document.documentElement.clientWidth - 150;
            if(clientWidth < 1000){
            	clientWidth = 1000;
            }
            var clientHeight = document.documentElement.clientHeight - 200;
            if(clientHeight < 550){
            	clientHeight = 550;
            }
            BH_UTILS.bhWindow(html, '',[], {
                width: clientWidth,
                maxWidth: clientWidth,
                height: clientHeight,
                close:function(){
                    // 查询已选课程数量
                    querySelectCourseNum();
                    $(window).scrollTop(0);
                    reloadCourseList();
                    selectCourseIsOpen = false;
                }
            });
            $('.xsxk-xktx-tab .courses').height(clientHeight - 145);
            initTabs(type);
            CVDialog.restoreScroll();
            $('#cvAside').removeClass('cv-expand');
            event.stopPropagation();
            selectCourseIsOpen = true;
        }        
    } else if (type == 'course') {
        // 打开学生课表页面
    	var currentBatch = JSON.parse(sessionStorage.getItem('currentBatch'));
    	if(currentBatch.batchType == '02'){
    		window.open(BaseUrl + '/sys/xsxkapp/*default/expcurriculum.do');
    	}else {
    		window.open(BaseUrl + '/sys/xsxkapp/*default/curriculum.do');
    	}
        CVDialog.restoreScroll();
        $('#cvAside').removeClass('cv-expand');
        event.stopPropagation();
    } else if (type == 'top') {
        // 回到顶部事件
        $('body,html').animate({scrollTop:0},1000);
        CVDialog.restoreScroll();
        $('#cvAside').removeClass('cv-expand');
        event.stopPropagation();
    } else if (type == 'unsuccessful') {
        // 落选课程
        $('#cvAsideUser').html('');
        initUnsuccessful();
        CVDialog.unScroll();
        $('#cvAside').addClass('cv-expand');
    } else if(type == 'batch'){
    	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    	var timestamp = new Date().getTime();
        $.ajax({
            type: "get",
            url: BaseUrl + "/sys/xsxkapp/student/" + studentInfo.code + ".do?timestamp=" + timestamp,
            headers: {
                "token": sessionStorage.token
            },
            success: function(resp) {
                var code = resp.code;
                if (code != null && code == "1") {
                    studentInfo = resp.data;
                	if((studentInfo.electiveBatchList.length + studentInfo.expElectiveBatchList.length) == 1){
                		$.bhTip({
            				content: '只存在一个轮次，无需切换',
            				state: 'warning'
            			});
                		var electiveBatch = studentInfo.electiveBatchList[0];
                        studentInfo.electiveBatch = electiveBatch;
                        sessionStorage.setItem('studentInfo', JSON.stringify(studentInfo));
                        sessionStorage.setItem('currentBatch', JSON.stringify(electiveBatch));
                        sessionStorage.setItem('electiveIsOpen', electiveBatch.canSelect);
                	}else{
                		CVDialog.restoreScroll();
                        $('#cvAside').removeClass('cv-expand');
                		openElectiveBatchWindow(studentInfo, studentInfo.electiveBatchList, studentInfo.expElectiveBatchList);
                	}
                } else if (code == '2') {
                    var msg = resp.msg;
                    if (loginType == 'cas') {
                        // cas方式登录
                        $.bhTip({
                            content: '登录验证未通过',
                            state: 'danger'
                        });
                    } else {
                        // 其他方式登录，显示错误信息
                        $.bhTip({
                            content: msg,
                            state: 'danger'
                        });
                    }
                } else if (code == '302') {
                    $.bhTip({
                        content: '未登录用户',
                        state: 'danger'
                    });
                } else {
                    // 查询学生数据失败
                    $.bhTip({
                        content: '登录失败，请稍后重试',
                        state: 'danger'
                    });
                }
            }
        });
    } else if(type == 'score'){
    	window.open(BaseUrl + '/sys/xsxkapp/*default/scoredetail.do');
    	CVDialog.restoreScroll();
        $('#cvAside').removeClass('cv-expand');
        event.stopPropagation();
    }
}

/**
 * 打开轮次弹窗
 */
function openElectiveBatchWindow(studentInfo, electiveBatchList, expElectiveBatchList){
	var electiveBatchListHtml = $("#electiveBatch_list_select").html();
    var expElectiveBatchListHtml = $("#expElectiveBatch_list_select").html();
    var bodyhtml = "";
    var expBodyHtml = "";
    var currentBatch = JSON.parse(sessionStorage.getItem('currentBatch'));
    var selectedCode = currentBatch.code;
    var electiveBatchObj = null;
    var expElectiveBatchObj = null;
    var electiveBatchDisplay = 'cv-hide';
    var confirmInfo = '';
    for (var i = 0, elength = electiveBatchList.length; i < elength; i++) {
        electiveBatchObj = electiveBatchList[i];
        bodyhtml += "<tr class='electiveBatch-row'><td class='cv-electiveBatch-operate'>";
        if (electiveBatchObj.canSelect == '1') {
            if (selectedCode == electiveBatchObj.code) {
                bodyhtml += "<div><input class='cv-electiveBatch-select' name='electiveBatchSelect' type='radio' data-value='" + JSON.stringify(electiveBatchObj) + "' checked='checked' value='' /></div>";
                confirmInfo = electiveBatchObj.confirmInfo;
                if (electiveBatchObj.needConfirm == '1' && electiveBatchObj.isConfirmed != '1') {
                    electiveBatchDisplay = 'cv-show';
                }
            } else {
                bodyhtml += "<div><input class='cv-electiveBatch-select' name='electiveBatchSelect' type='radio' data-value='" + JSON.stringify(electiveBatchObj) + "' value='' /></div>";
            }
        }
        bodyhtml += "</td>";
        bodyhtml += "<td class='cv-electiveBatch-name'><div>" + electiveBatchObj.name + "</div></td>";
        bodyhtml += "<td class='cv-electiveBatch-kssj'><div>" + electiveBatchObj.beginTime + "</div></td>";
        bodyhtml += "<td class='cv-electiveBatch-jssj'><div>" + electiveBatchObj.endTime + "</div></td>";
        bodyhtml += "<td class='cv-electiveBatch-sfkxq'><div>" + (electiveBatchObj.multiCampus=='1'?'是':'否') + "</div></td>";
        bodyhtml += "<td class='cv-electiveBatch-sfct'><div>" + (electiveBatchObj.noCheckTimeConflict=='1'?'是':'否') + "</div></td>";
        bodyhtml += "<td class='cv-electiveBatch-cause'>";
        if (electiveBatchObj.canSelect != '1') {
            bodyhtml += "<div>" + electiveBatchObj.noSelectReason + "</div>";
        }
        bodyhtml += "</td></tr>";
    }
    electiveBatchListHtml = electiveBatchListHtml.replace('@electiveBatchBody', bodyhtml)
        .replace('@electiveBatchDisplay', electiveBatchDisplay)
        .replace('@confirmInfo', confirmInfo);
    if(expElectiveBatchList.length>0){
    	for(var i=0;i<expElectiveBatchList.length;i++){
    		expElectiveBatchObj = expElectiveBatchList[i];
    		expBodyHtml += "<tr class='electiveBatch-row'><td class='cv-electiveBatch-operate'>";
        	if (selectedCode == expElectiveBatchObj.code) {
        		expBodyHtml += "<div><input class='cv-electiveBatch-select' name='electiveBatchSelect' type='radio' data-value='" + JSON.stringify(expElectiveBatchObj) + "' checked='checked' value='' /></div>";
            } else {
            	expBodyHtml += "<div><input class='cv-electiveBatch-select' name='electiveBatchSelect' type='radio' data-value='" + JSON.stringify(expElectiveBatchObj) + "' value='' /></div>";
            }
        	expBodyHtml += "</td>";
        	expBodyHtml += "<td class='cv-electiveBatch-name'><div>" + expElectiveBatchObj.name + "</div></td>";
        	expBodyHtml += "<td class='cv-electiveBatch-jssj'><div>" + expElectiveBatchObj.beginTime + "</div></td>";
        	expBodyHtml += "<td class='cv-electiveBatch-jssj'><div>" + expElectiveBatchObj.endTime + "</div></td>";
        	expBodyHtml += "<td class='cv-electiveBatch-sfkxq'><div>" + expElectiveBatchObj.crossCampusName + "</div></td>";
        	expBodyHtml += "<td class='cv-electiveBatch-sfkct'><div>" + expElectiveBatchObj.conflictName + "</div></td>";
        	expBodyHtml += "<td class='cv-electiveBatch-name'><div>" + expElectiveBatchObj.conflictTime + "</div></td>";
        	expBodyHtml += "</td></tr>";
    	}
    	electiveBatchListHtml = electiveBatchListHtml + expElectiveBatchListHtml.replace('@expElectiveBatchBody', expBodyHtml);
    }
    var clientWidth = document.documentElement.clientWidth - 150;
    var clientHeight = document.documentElement.clientHeight - 200;
    if(clientHeight < 550){
    	clientHeight = 550;
    }
	BH_UTILS.bhWindow(electiveBatchListHtml, '选择轮次',
		[{
			text:'确定',
            className:'bh-btn-primary',
            callback:function(){
                if($('.cv-electiveBatch-select:checked').length == 0){
                	$.bhTip({
        				content: '请选择轮次',
        				state: 'warning'
        			});
                	return false;
                }else{
                	var selected = JSON.parse($('.cv-electiveBatch-select:checked').eq(0).attr('data-value'));
                	if($('.electiveBatchXznr').hasClass('cv-show')){
                		if(!$('.electiveBatchXznr #tyxz-input').prop('checked')){
                			$.bhTip({
                				content: '请阅读须知并同意',
                				state: 'warning'
                			});
                			return false;
                		}
                		
                	}
                	if($('.electiveBatchXznr').hasClass('cv-show')){
                		//修改学生已同意须知的状态
                    	selected.isConfirmed = '1';
                    	$.each(studentInfo.electiveBatchList, function(index, obj){
                    		if(obj.code == selected.code){
                    			obj.isConfirmed = '1';
                    		}
                    	});
                    	var makeSureParam = {
                			electiveBatchCode: selected.code,
                			studentCode: studentInfo.code
                    	};
                    	makeSureLcxz(makeSureParam).done(function(resp){
                    		if(resp.code == '1'){
                    			dealWithStudentInfo(studentInfo, selected);
                    		}else{
                    			$.bhTip({
                    				content: '修改学生已同意须知的状态失败',
                    				state: 'danger'
                    			});
                    		}
                    	});
                	}else{
                		dealWithStudentInfo(studentInfo, selected);
                	}
                }
            }
		},{
			text:'关闭',
            className:'bh-btn-default',
            callback:function(){
                
            }
		}], {
			width: clientWidth,
    		maxWidth: clientWidth,
    		height: clientHeight,
    		closeButtonSize: 0
		}
	);
	
	var maxHeight = 340 - $('.electiveBatch .lc-container').height() - $('.expElectiveBatch').height();
    if(maxHeight < 100){
    	maxHeight = 100;
    }
    $('.electiveBatchXznr .xznr-content').css({
        'max-height': maxHeight
    });
	
	//绑定按钮切换事件
	$('.electiveBatch-list-table').off('click').on('click', '.cv-electiveBatch-select', function(e){
		var electiveBatch = JSON.parse($(e.currentTarget).attr('data-value'));
		if(electiveBatch.needConfirm == '1' && electiveBatch.isConfirmed != '1'){
			$('.electiveBatchXznr').removeClass('cv-show').removeClass('cv-hide').addClass('cv-show');
		}else{
			$('.electiveBatchXznr').removeClass('cv-show').removeClass('cv-hide').addClass('cv-hide');
		}
		$('.electiveBatchXznr .xznr-content').html(electiveBatch.confirmInfo);
	});
	
	if($('.cv-electiveBatch-select:checked').length == 0 && $('.cv-electiveBatch-select').length > 0){
		$('.cv-electiveBatch-select').eq(0).prop('checked', true).trigger('click');
	}
}

/**
 * 处理studentInfo
 */
function dealWithStudentInfo(studentInfo, electiveBatch){
	var token = sessionStorage.getItem('token');
	// 在本地缓存中保存登录的学生信息
	studentInfo.electiveBatch = electiveBatch;
    sessionStorage.setItem('studentInfo', JSON.stringify(studentInfo));                
    sessionStorage.setItem('currentBatch', JSON.stringify(electiveBatch));
    sessionStorage.setItem('electiveIsOpen', electiveBatch.canSelect);
    if(electiveBatch.batchType == '02'){
    	url = BaseUrl 
        + "/sys/xsxkapp/*default/expcurriculavariable.do?token=" 
        + token;
    }else if(electiveBatch.typeCode == '01'){
		url = BaseUrl 
        + "/sys/xsxkapp/*default/curriculavariable.do?token=" 
        + token;
	}else if(electiveBatch.typeCode == '02'){
		url = BaseUrl
        + "/sys/xsxkapp/*default/grablessons.do?token="
        + token;
	}
	window.location.href = url;
}

// 初始化落选课程
function initUnsuccessful() {
    var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    var studentCode = studentInfo.code;
    var isRead = '1';
    queryUnSuccessful(studentCode, isRead, studentInfo.electiveBatch.code).done(function(resp){
        var code = resp.code;
        if (code != null && code == '1') {
            var dataList = resp.dataList;
            buildUnsuccessfulTable(dataList);
        } else if (code == '302') {
            sessionStorage.removeItem('token');
            sessionStorage.removeItem('studentInfo');
            window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
        }
    });
}

function buildUnsuccessfulTable(dataList) {
    if (dataList != null && dataList.length > 0) {
        var bodyHtml = '';
        var data = null;
        for (var i = 0, length = dataList.length; i < length; i++) {
            data = dataList[i];
            var rowTemplate = $('#tpl-stundent-unsuccessful-row').html();
            var date = data.deleteOperateTime;
            date = date.substring(0, 10);
            var courseName = data.courseName;
            var courseIndex = data.courseIndex;
            if (courseIndex != null && courseIndex != '') {
                courseName += '[' + courseIndex + ']';
            }
            var sportName = data.sportName;
            if (sportName != null && sportName != '') {
                courseName += '(' + sportName + ')';
            }
            var teacherName = data.teacherName;
            if (teacherName == null) {
                teacherName = '...';
            }
            if (courseName == null || courseName == '') {
                courseName = '...';
            }
            var result = data.deleteOperateTypeName;
            bodyHtml += rowTemplate.replace('@date', date)
                .replace('@courseName', courseName)
                .replace('@teacherName', teacherName)
                .replace('@result', result);
        }
        var html = '';
        var template = $('#tpl-stundent-unsuccessful').html();
        html += template.replace('@body', bodyHtml);
        $('#cvUnsuccessfulCourse').html(html);
    } else {
        $('#cvUnsuccessfulCourse').html('无落选课程');
    }
}

//初始化tab
function initTabs(type){
    $('.xsxk-xktx-tab').jqxTabs({
        position: 'top'
    });
    initTabContent(0, type);
    $('.xsxk-xktx-tab').on('tabclick', function(event) {
        var tabIndex = event.args.item;
        initTabContent(tabIndex, type);
    });
}

function initTabContent(tabIndex, type) {
    var $element = $('.xsxk-xktx-tab-content-' + tabIndex + ' .courses');
    var timeTemp = new Date().getTime();
    var url = '';
    if (type == 'volunteer') {
        url = './selectedvolunteer.do';
        if (tabIndex == '0') {
            if (url != '') {
                $element.load(url + '?timetemp=' + timeTemp, function(){
                    initSelectCourse();               
                });
            }        
        } else if (tabIndex == '1') {
            if (url != '') {
                $element.load(url + '?timetemp=' + timeTemp, function(){
                    initPublicCourse();               
                });
            }
        } else if (tabIndex == '2') {
            $element.load('./departurelog.do', function(){
                initDeparturelog();
            });
        } else if (tabIndex == '3') {
        	initMessageQueue($element);
        }
    } else if (type == 'grablessons') {
        url = './selectedcourse.do';
        if (tabIndex == '0') {
            if (url != '') {
                $element.load(url + '?timetemp=' + timeTemp, function(){
                    initSelectCourse();               
                });
            }        
        } else if (tabIndex == '1') {
            $element.load('./departurelog.do', function(){
                initDeparturelog();
            });
        } else if (tabIndex == '2') {
        	initMessageQueue($element);
        }
    }
    
    
}

// 初始化学生基础信息
function initStudentInformation() {
    var studentInfo = JSON.parse(sessionStorage.getItem("studentInfo"));
    var xh = studentInfo.code;
    queryStudentInformation(xh).done(function(resp){
        var code = resp.code;
        if(code != null && code == '1') {
            // 查询数据成功
            var data = resp.data;
            var studentHtml = $('#tpl-stundent-information').html();
            var html = '';
            var totalCredit = data.totalCredit;
            totalCredit = totalCredit == null ? 0 : totalCredit;
            var getCredit = data.getCredit;
            getCredit = getCredit == null ? 0 : getCredit;
            var needCredit = data.needCredit;
            needCredit = needCredit == null ? 0 : needCredit;
            var departmentName = data.departmentName;
            departmentName = departmentName == null ? '...' : departmentName;
            var creditProportion = data.getCreditProportion;
            creditProportion = creditProportion == null ? '0' : creditProportion;
            var grade = data.grade;
            grade = grade == null ? '...' : grade;

            var headImageUrl = null;
            var gender = data.gender;
            if (gender != null && gender == '1') {
                headImageUrl = resUrl + '/public/images/user/male56_76.png';
            } else {
                headImageUrl = resUrl + '/public/images/user/female56_76.png';
            }
           
            // 当前校区
            var currentCampus = JSON.parse(sessionStorage.getItem('currentCampus'));
            html += studentHtml.replace('@name', data.name)
                .replace('@college', data.collegeName)
                .replace('@department', departmentName)
                .replace('@headImageUrl', headImageUrl)
                .replace('@grade', grade + "级")
                .replace('@getCreditProportion', creditProportion + '%')
                .replace('@totalCredit', totalCredit)
                .replace('@getCredit', getCredit)
                .replace('@needCredit', needCredit)
                .replace('@campusName', "切换校区 : " + currentCampus.name)
                .replace('@code', currentCampus.code);
            $('#cvAsideUser').html(html);

            // 根据选课轮次中的参数设置校区是否可切换
            var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
            var electiveBatch = studentInfo.electiveBatch;
            //sessionStorage.setItem('currentBatch', JSON.stringify(electiveBatch));
            //initMenuControl();
            if("02" != electiveBatch.batchType){            	
            	// 初始化饼图
            	var studentInfo = JSON.parse(sessionStorage.getItem("studentInfo"));
            	var xkxfQueryParam = {
            			xh: studentInfo.code,
            			xklcdm: studentInfo.electiveBatch.code,
            			xklclx: studentInfo.electiveBatch.batchType
            	};
            	queryXkxf(xkxfQueryParam).done(function(resp){
            		if(resp.code == '1'){
            			//学分图表数据
            			totalCredit = resp.data.totalCredit;
            			getCredit = resp.data.getCredit;
            			needCredit = resp.data.needCredit;
            			//2019-04-22:wzp修改成手绘
            			var _data=[{'num':totalCredit == null ? 0 : totalCredit,'name':'总学分'},
            			           {'num':getCredit == null ? 0 : getCredit,'name':'已获学分'},
            			           {'num':needCredit == null ? 0 : needCredit,'name':'已选学分'}];
            			var cvs = document.getElementById("cvCreditChart");
            			Xfimage.draw(cvs,_data);
            			var _data1 = [{
                            'num': totalCredit == null ? 0 : totalCredit,
                            'name': '总学分'
                        },{
                            'num': needCredit == null ? 0 : needCredit,
                            'name': '已选学分'
                        }];
                        Xfimage.drawInfo('#cvCreditInfo', _data1);
            		}else{
            			$.bhTip({
            				content: resp.msg,
            				state: 'danger'
            			});
            		}
            	});
            	var multiCampus = electiveBatch.multiCampus;
            	var multiTeachCampus = electiveBatch.multiTeachCampus;
            	if((multiCampus != null && multiCampus == '1') || (multiTeachCampus != null && multiTeachCampus == '1')) {
            		// 绑定切换校区按钮点击事件
            		$("#changeCampus").on("click", function(e){
            			var campusList = JSON.parse(sessionStorage.getItem('campusList'));
            			if(multiTeachCampus == null || multiTeachCampus=='0'){
            				campusList = campusList.filter(function(item) {
            					return studentInfo.teachCampus == item.reserve2;
            				});
            			}
            			CVDropdownDialog.init($(this), campusList, 'campus', 'slide');
            		});
            	}
            }
        } else {
            // 查询数据失败
            $('#cvAsideUser').html("<p>未查询到数据</p>");
        }
    });
}


function initMessageQueue($element){
	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    var electiveBatch = studentInfo.electiveBatch;
	var param = {
		studentCode: studentInfo.code,
		electiveBatchCode: electiveBatch.code
	};
	queryStudentQueue(param).done(function(res){
		if(res.code == '1'){
			var queueHtml = $('#message_queue_list').html();
			var rowHtml = $('#message_queue_list_row').html();
			var bodyHtml = '';
			if(res.dataList.length > 0){
				//对结果进行排序
				var result = [];
				$.each(res.dataList, function(index, obj){
					if(obj.comment === '0'){
						result.unshift(obj);
					}else{
						result.push(obj);
					}
				});
				var state, czlx, kch, kcm, kxh, skjs, sksj, kclb, kcxz, xf;
				$.each(result, function(index, obj){
					state = obj.comment === '0'?'队列处理中':obj.comment;
					czlx = obj.operationType == '1'?'添加':'删除';
					kch = obj.courseNumber?obj.courseNumber:'';
					kcm = obj.courseName?obj.courseName:'';
					kxh = obj.courseIndex?obj.courseIndex:'';
					skjs = obj.teacherName?obj.teacherName:'';
					sksj = obj.teachingPlace?obj.teachingPlace:'';
					kclb = obj.courseTypeName?obj.courseTypeName:'';
					kcxz = obj.courseNatureName?obj.courseNatureName:'';
					xf = obj.credit?obj.credit:'';
					bodyHtml += rowHtml.replace(/@state/g, state)
									   .replace(/@czlx/g, czlx)
									   .replace(/@kch/g, kch)
									   .replace(/@kcm/g, kcm)
									   .replace(/@kxh/g, kxh)
									   .replace(/@skjs/g, skjs)
									   .replace(/@sksj/g, sksj)
									   .replace(/@kclb/g, kclb)
									   .replace(/@kcxz/g, kcxz)
									   .replace(/@xf/g, xf);
				});
			}
			queueHtml = queueHtml.replace('@queueBody', bodyHtml);
			$element.html(queueHtml);
		}else{
			$.bhTip({
				content: '查询消息队列失败',
				state: 'danger'
			});
		}
	});
}

