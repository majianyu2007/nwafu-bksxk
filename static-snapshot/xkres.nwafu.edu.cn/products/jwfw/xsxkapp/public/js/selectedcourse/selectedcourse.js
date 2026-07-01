/**
 * 初始化系统参数标题（设置页面学年学期、周次、校区信息）
 */
;
(function(_mode) {

    _mode.titleInit = function($dom) {
        titleInit($dom);
    };

    function titleInit($dom) {
        // 当前选课的学年，学期，周次
    	var xklc = JSON.parse(sessionStorage.getItem('currentBatch'));
        // 学年学期名称
        var schoolTermName = xklc.schoolTermName;
        // 周次范围
        var weekRange = xklc.weekRange;
        var html = schoolTermName + "&nbsp;" + weekRange;
        // 当前校区
        var currentCampus = JSON.parse(sessionStorage.getItem('currentCampus'));
        var teachingClassType = sessionStorage.getItem('teachingClassType');
        if (teachingClassType != 'QXKC' && currentCampus != null) {
            html += '<span style="margin-left: 8px;">' + currentCampus.name + '<span>' +
            		'<span class="home-change-campus" style="margin-left: 4px;color: #047ADC;cursor: pointer;">切换<span>';
        }
        $dom.html(html);
    }
})(window.CVTitleMode = window.CVTitleMode || {});

/**
 * 页脚信息
 */
;
(function(_mode) {

    _mode.init = function() {
        setCelebrityFamous();
    };

    function setCelebrityFamous() {
        var dataList = JSON.parse(sessionStorage.getItem('celebrityFamous'));
        if (dataList != null && dataList.length > 0) {
            initFooterMessage(dataList[randomNumBoth(0, dataList.length - 1)]);
        } else {
            queryCelebrityFamous().done(function(resp) {
                var code = resp.code;
                if (code != null && code == '1') {
                    var dataList = resp.dataList;
                    if (dataList != null && dataList.length > 0) {
                        var randomIndex = randomNumBoth(0, dataList.length - 1);
                        initFooterMessage(dataList[randomIndex]);
                    }
                }
            });
        }
        // 设置页脚固定在页面底部
        setContentMinHeight($('.main').children('article'));
    };

    /**
     * 设置页面数据
     */
    function initFooterMessage(_data) {
        $("#ecDiv").html(_data.englishContent);
        $("#cDiv").html(_data.content);
        $("#authorDiv").html(_data.author);
    };

    /**
     * 数字区间取随机数
     */
    function randomNumBoth(Min, Max) {
        var Range = Max - Min;
        var Rand = Math.random();
        //四舍五入
        var num = Min + Math.round(Rand * Range);
        return num;
    };
})(window.CVFotterMessage = window.CVFotterMessage || {});

/**
 * 选课结果
 */
;
(function(_course) {

    _course.init = function() {
        initCourseResultList();
    };

    function initCourseResultList() {
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var studentCode = studentInfo.code; // 学号
        var queryParam = {
            'studentCode': studentCode,
            'electiveBatchCode':studentInfo.electiveBatch.code
        };
        queryChooseCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                buildCourseResultList(resp.dataList);
            } else if (code != null && code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                queryError();
            }
        });
    }

    function buildCourseResultList(dataList) {
        if (dataList != null && dataList.length > 0) {
            var html = '';
            var length = dataList.length;
            var kcList = [];
            var testList = [];
            var a = 0, b = 0;
            
            for (a = 0; a < length; a++) {
                if (dataList[a].isTest == '1') {
                	testList.push(dataList[a]);
                }else{
                	kcList.push(dataList[a]);
                }
            }
            var kcLength = kcList.length;
            var testLength = testList.length;
            
            var jcdgShow = 'cv-hide';
            var bookParam = JSON.parse(sessionStorage.getItem('bookParam'));
            if(bookParam.needBook == '1'){
            	jcdgShow = 'cv-show';
            }
            for (a = 0; a < kcLength; a++) {
            	var data = kcList[a];
            	var rowTemplate = $('#tpl-selectcourse-list-row').html();
                	
            	//rowTemplate = $('#tpl-selectcourse-test-list-row').html();
                
            	var courseTypeName = data.courseTypeName;
                if (courseTypeName == null) {
                    courseTypeName = '-';
                }

                var courseNatureName = data.courseNatureName;
                if (courseNatureName == null) {
                	courseNatureName = '-';
                }

                var teacherName = data.teacherName;
                if (teacherName == null) {
                    teacherName = '未安排教师';
                }

                var teachingPlace = data.teachingPlace;
                if (teachingPlace == null) {
                    teachingPlace = '未安排时间地点';
                }

                var isConflict = data.isConflict;
                if (isConflict != null && isConflict == '1') {
                    isConflict = '冲突';
                } else {
                    isConflict = '不冲突';
                }
                var conflictDesc = data.conflictDesc;
                if (conflictDesc == null) {
                    conflictDesc = "";
                }

                var courseName = data.courseName;
                var sportName = data.sportName;
                if (courseName == null) {
                    courseName = '-';
                }
                if (sportName != null) {
                    courseName = courseName + '(' + sportName + ')';
                }

                var campusName = data.campusName;
                if (campusName == null) {
                    campusName = '-';
                }

                var publicCourseTypeName = data.publicCourseTypeName;
                if (publicCourseTypeName == null) {
                	publicCourseTypeName = '-';
                }

                var isDisabled = '';
                var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
                var isTest = data.isTest;
                if ((electiveIsOpen != null && electiveIsOpen == '1') && (isTest == null || isTest != '1')) {
                    isDisabled = '';
                } else {
                    isDisabled = 'disabled="disabled"';
                }

                var needOrderBook = data.needOrderBook;
                var oBclass = ' class="cv-jcDetail" ';
                var isDisabledBook = '';
                if (needOrderBook != '1') {
                	isDisabledBook = 'disabled="disabled"';
                	oBclass = '';
                }
                var isTest = data.isTest;
                if (isTest != null && isTest == '1') {
                    courseTypeTip = '实验课';
                } else {
                    courseTypeTip = '理论课';
                }

                var bookBtnHtml = '';
                var bookParam = JSON.parse(sessionStorage.getItem('bookParam'));
                var isDisabled_dg = '';
                var isDisabled_tdg = '';
                var dgclass = ' class="course-book"';
                var tdgclass = ' class="course-unbook"';
                if(bookParam.canSelectBook == '1' && data.hasBook=='1' /*&& (data.needBook=='0' || data.needBook=='5')*/){
                }else{
                	isDisabled_dg = 'disabled="disabled"';
                	dgclass = '';
                }
                
                if(bookParam.canDeleteBook == '1' && (data.hasBook=='1' || (data.needBook=='1' || data.needBook=='5'))){
                }else{
                	isDisabled_tdg = 'disabled="disabled"';
                	tdgclass = '';
                }

                bookBtnHtml += '<br><a href="javascript:void(0)" teachingClassID="' + data.teachingClassID + '"' + isDisabled_dg + dgclass + '>订购教材</a>';
            	bookBtnHtml += '<br><a href="javascript:void(0)" teachingClassID="' + data.teachingClassID + '"' + isDisabled_tdg + tdgclass + '>退订教材</a>';
            	var needbook = '';
                if(bookParam.needBook == '1'){
                	if(data.needBook == '1'){
                		needbook = '已订购';
                	}else if(data.needBook == '5'){
                		needbook = '订购部分';
                	}else{
                		needbook = '未订购';
                	}
                }
                needbook+='<div><a '+oBclass+' tcid="' + data.teachingClassID + '" href="javascript:void(0);"  '+isDisabledBook+'>教材信息</a></div>';
                html += rowTemplate.replace('@courseNumber', data.courseNumber + '[' + data.courseIndex + ']')
                    .replace('@courseName', courseName)
                    .replace('@teacherName', teacherName)
                    .replace('@courseNatureName', courseNatureName)
                    .replace('@courseTypeName', courseTypeName)
                    .replace('@publicCourseTypeName', publicCourseTypeName)
                    .replace('@teachingPlace', teachingPlace)
                    .replace('@credit', data.credit)
                    .replace('@hours', data.hours)
                    .replace('@campusName', campusName)
                    .replace(/@teachingClassID/g, data.teachingClassID)
                    .replace('@isConflict', isConflict)
                    .replace('@conflictDesc', conflictDesc)
                    .replace('@bookBtnHtml', bookBtnHtml)
                    .replace('@jcdgShow', jcdgShow)
                    .replace('@needbook', needbook)
                    .replace('@isDisabled', isDisabled);
                	
                
                if(data.hasTest == '1'){
                	for (b = 0; b < testLength; b++) {
                		var test_data = testList[b];
                		if(test_data.teachingClassID == data.testTeachingClassID){
                			var test_rowTemplate = $('#tpl-selectcourse-test-list-row').html();
                			
                			var test_courseTypeName = test_data.courseTypeName;
                			if (test_courseTypeName == null) {
                				test_courseTypeName = '-';
                			}
                			
                			var test_courseNatureName = test_data.courseNatureName;
                			if (test_courseNatureName == null) {
                				test_courseNatureName = '-';
                			}

                			var test_publicCourseTypeName = test_data.publicCourseTypeName;
                			if (test_publicCourseTypeName == null) {
                				test_publicCourseTypeName = '-';
                			}
                			
                			var test_teacherName = test_data.teacherName;
                			if (test_teacherName == null) {
                				test_teacherName = '未安排教师';
                			}
                			
                			var test_teachingPlace = test_data.teachingPlace;
                			if (test_teachingPlace == null) {
                				test_teachingPlace = '未安排时间地点';
                			}
                			
                			var test_isConflict = test_data.isConflict;
                			if (test_isConflict != null && test_isConflict == '1') {
                				test_isConflict = '冲突';
                			} else {
                				test_isConflict = '不冲突';
                			}
                			var test_conflictDesc = test_data.conflictDesc;
                			if (test_conflictDesc == null) {
                				test_conflictDesc = "";
                			}
                			
                			var test_courseName = test_data.courseName;
                			var test_sportName = test_data.sportName;
                			if (test_courseName == null) {
                				test_courseName = '-';
                			}
                			if (test_sportName != null) {
                				test_courseName = test_courseName + '(' + test_sportName + ')';
                			}
                			
                			var test_campusName = test_data.campusName;
                			if (test_campusName == null) {
                				test_campusName = '-';
                			}
                			
                			var test_isDisabled = '';
                			var test_electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
                			var test_isTest = test_data.isTest;
                			if ((test_electiveIsOpen != null && test_electiveIsOpen == '1') && (test_isTest == null || test_isTest != '1')) {
                				test_isDisabled = '';
                			} else {
                				test_isDisabled = 'disabled="disabled"';
                			}
                			
                			var test_isTest = test_data.isTest;
                			if (test_isTest != null && test_isTest == '1') {
                				test_courseTypeTip = '实验课';
                			} else {
                				test_courseTypeTip = '理论课';
                			}
                			var test_needbook = '';
                            if(bookParam.needBook == '1'){
                            	if(test_data.needBook == '1'){
                            		test_needbook = '已订购';
                            	}else{
                            		test_needbook = '未订购';
                            	}
                            }

                			
                			html += test_rowTemplate.replace('@courseNumber', test_data.courseNumber + '[' + test_data.courseIndex + ']')
                			.replace('@courseName', test_courseName)
                			.replace('@teacherName', test_teacherName)
                			.replace('@courseNatureName', test_courseNatureName)
                			.replace('@courseTypeName', test_courseTypeName)
                			.replace('@publicCourseTypeName', test_publicCourseTypeName)
                			.replace('@teachingPlace', test_teachingPlace)
                			.replace('@credit', test_data.credit)
                			.replace('@hours', test_data.hours)
                			.replace('@campusName', test_campusName)
                			.replace('@teachingClassID', test_data.teachingClassID)
                			.replace('@isConflict', test_isConflict)
                			.replace('@conflictDesc', test_conflictDesc)
                			.replace('@jcdgShow', jcdgShow)
                			.replace('@needbook', test_needbook)
                			.replace('@isDisabled', test_isDisabled);
                		}
                    }
                }
            }
            $('#selectedCourse').html(html);

            var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
            var electiveBatch = studentInfo.electiveBatch;
            var electiveTacticCode = electiveBatch.tacticCode;
            if (electiveTacticCode != null && electiveTacticCode == '02') {
                $('.withdrew').attr('disabled', 'disabled');
            } else {
                // 绑定删除事件
                $('.withdrew').on('click', function(event) {
                    var disabled = $(event.currentTarget).attr('disabled');
                    if (disabled == null) {
                   	var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
                       var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
                       var electiveBatch = studentInfo.electiveBatch;
                       //若未开放，则重新请求是否开放
                       if(!electiveIsOpen || electiveIsOpen != '1'){
                       	var resp = queryXklcSfkfBySync({xklcdm: electiveBatch.code});
                   		if(resp.msg == '1'){
                   			sessionStorage.setItem('electiveIsOpen', '1');
                   			electiveIsOpen = '1';
                   		}
                       }
                       //判断是否开放
                       if (!electiveIsOpen || electiveIsOpen != '1') {
                       	$.bhTip({
                   			content: '轮次未开放',
                   			state: 'danger'
                   		});
                       	return false;
                       }
                       CVDeleteCourseResults.deleteResult(event);
                   }
               });
            }
            $('#cvSelectCourse .cv-selected-course').off('click', '.course-book').on('click', '.course-book', function(e){
            	var dialogData = new Object();
                dialogData.title = '确认订购教材';
                dialogData.content = '确认订购这门课程的教材吗？';
                dialogData.type = 'course-book';
                dialogData.jxbid = $(e.currentTarget).attr('teachingclassid');
                CVDialogSelectCourse.show(dialogData, e);
            });
            $('#cvSelectCourse .cv-selected-course').off('click', '.course-unbook').on('click', '.course-unbook', function(e){
            	var dialogData = new Object();
            	dialogData.title = '确认退订教材';
            	dialogData.content = '确认退订这门课程的教材吗？';
            	dialogData.type = 'course-unbook';
            	dialogData.jxbid = $(e.currentTarget).attr('teachingclassid');
            	CVDialogSelectCourse.show(dialogData, e);
            });
            $('#cvSelectCourse .cv-selected-course').off('click', '.cv-jcDetail').on('click', '.cv-jcDetail', function(e){
            	var jxbid = $(e.currentTarget).attr('tcid');
            	window.open(BaseUrl + '/sys/xsxkapp/*default/jcdetail.do?jxbid=' + jxbid);
            });
        } else {
            $('#selectedCourse').html('没有已选课程');
        }
        
    }

    function queryError() {
        $('#cvSelectCourse').html('<p>数据异常，请稍后重试。</p>');
    }

})(window.CVCourseResult = window.CVCourseResult || {});

/**
 * 删除选课结果
 */
;
(function(_public) {

    _public.deleteResult = function(e) {
        deleteCourseResult(e);
    };

    function deleteCourseResult(e) {
        var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
        if (electiveIsOpen != null && electiveIsOpen == '1') {
            var dialogData = new Object();
            dialogData.title = '确认退选';
            dialogData.content = '确认退选这门课程吗？';
            dialogData.type = 'withdrew';
            CVDialogSelectCourse.show(dialogData, e);
        }
    }
})(window.CVDeleteCourseResults = window.CVDeleteCourseResults || {});

/**
 * 对话框
 */
;
(function(_dialog) {
    /**
     * 显示对话框
     * @param _data {object}
     * @param _data.title {string} 课程标题
     */
    _dialog.show = function(_data, e) {
    	if(_data.type == 'course-unbook' || _data.type=='course-book'){
    		showDialogForJc(_data,e);
    	}else{
    		showDialog(_data, e);
    	}
    };

    _dialog.showSuccess = function(_data) {
        showSuccess(_data);
    };

    _dialog.showDanger = function(_data) {
        showDanger(_data);
    };

    /**
     * 移除弹框
     */
    _dialog.remove = function() {
        removeDialog();
    };

    function showSuccess(_data) {
        var template =
            '<div id="cvDialog" class="cv-dialog cv-success">' +
            '<div>' +
            '<div class="cv-body">' +
            '<img class="cv-mb-16" src="public/images/curriculaVariable/dialog-icon.png">' +
            '<h2 class="cv-mb-8">@title</h2>' +
            '<div>@content</div>' +
            '</div>' +
            '<div class="cv-foot">' +
            '<div class="cv-sure cvBtnFlag">确认</div>' +
            '</div>' +
            '</div>' +
            '</div>';
        var title = _data.title;
        var content = _data.content;
        var html = template.replace('@title', title).replace('@content', content);

        var $dialog = $(html);
        $('body').append($dialog);

        //点击页脚按钮的事件
        $dialog.on('click', '.cvBtnFlag', function() {
            btnHandle($(this));
        });
    }

    function showDanger(_data) {
        var template =
            '<div id="cvDialog" class="cv-dialog cv-danger">' +
            '<div>' +
            '<div class="cv-body">' +
            '<img class="cv-mb-16" src="public/images/curriculaVariable/dialog-icon.png">' +
            '<h2 class="cv-mb-8">@title</h2>' +
            '<div>@content</div>' +
            '</div>' +
            '<div class="cv-foot">' +
            '<div class="cv-sure cvBtnFlag">确认</div>' +
            '</div>' +
            '</div>' +
            '</div>';
        var title = _data.title;
        var content = _data.content;
        var html = template.replace('@title', title).replace('@content', content);

        var $dialog = $(html);
        $('body').append($dialog);

        //点击页脚按钮的事件
        $dialog.on('click', '.cvBtnFlag', function() {
            btnHandle($(this));
        });
    }
    
    function showDialogForJc(_data, e){
    	var istjc = _data.type == 'course-unbook';
    	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    	var currentBatch = JSON.parse(sessionStorage.getItem('currentBatch'));
    	queryJxbJcResult({xh: studentInfo.code, jxbid: _data.jxbid, xklcdm: currentBatch.code}).done(function(resp){
    		if(resp.code==1){
    			var html=istjc?"":"<div>如果订购教材请选择【是】；如果不订购教材请选择【否】并选择不订购原因，否则无法确认；</div>";
    			html += '<br><table id="jcxx" class="table syk-table"><thead>';
    			var jcFieldArr = [{'width':'15%','caption':istjc?'是否退订教材':'是否订购教材','field':'SFDG'},
    			                  {'width':'20%','caption':'不订购教材原因','field':'WDGYY'},
    			                  {'width':'15%','caption':'ISBN','field':'ISBN'},
    			                  {'width':'30%','caption':'教材名称','field':'SM'},
    			                  {'width':'10%','caption':'著作者','field':'ZZZ'}]; 
    			$.each(jcFieldArr, function(index, obj){
					if(obj.width){
						html += '<th style="width:' + obj.width + ';">';
					}else{
						if(obj.field=='JCBH'){
							html += '<th hidden="true"> ';
						}else{
							html += '<th>';
						}
					}
					html += obj.caption + '</th>';
				});
				html += '</thead><tbody>';
				
				if(resp.dataList.length > 0){
					$.each(resp.dataList, function(index, obj){
						if(obj.wid){
							obj = JSON.parse(obj.wid);
						}else{
							obj = {};
						}
						html += '<tr>';
						$.each(jcFieldArr, function(index1, obj1){
							if(obj1.field=='SFDG'){
								html += '<td><select jcbh="'+obj['JCBH']+'" onchange="changeJcWdgyy(this,'+istjc+')" style="width:50px" name="sfdg" ' + ((istjc && obj.SFDG!=='1' || !istjc && obj.SFDG=='1')?'disabled="disabled"':'') + '>';
								if(istjc){
									if(obj.SFDG=='1'){
										html += ' <option value="1">是</option><option value="0" selected="selected">否</option> ';	
									}else{
										html += ' <option value="1" selected="selected">是</option><option value="0">否</option> ' ;
									}
								}else{
									if(obj.SFDG=='1'){
										html += ' <option value="1" selected="selected">是</option><option value="0">否</option> ' ;
									}else{
										html += ' <option value="1">是</option><option value="0" selected="selected">否</option> ' ;
									}
								}
								html +="</select></td>";
							}else if(obj1.field=='WDGYY'){
								var canselect = ((/*obj.SFDG=='0' &&*/ istjc)||(obj.SFDG=='1' && !istjc))?' disabled="disabled"':'';
								var selectJctdyy = '<select'+canselect+' class="bh-form-control jctdyy"><option value="***">请选择</option>';
						    	$.each(JSON.parse(sessionStorage.getItem('dictionary')).TJCYY,function(index,item){
						    		selectJctdyy += '<option '+ (obj.WDGYY==item.code?" selected":"") +' value="'+item.code+'">'+item.name+'</option>';
						    	});
						    	selectJctdyy += '</select>';
								html += "<td>"+selectJctdyy+"</td>";
							}else{
								html += '<td><span title="' + (obj[obj1.field]?obj[obj1.field]:'') + '">' + (obj[obj1.field]?obj[obj1.field]:'') + '</span></td>';
							}
						});
						html += '</tr>';
					});
				}else{
					html += '<tr><td class="nodata" colspan="' + jcFieldArr.length + '">无数据</td></tr>';
				}
				html += '</tbody></table>';
				BH_UTILS.bhWindow(html, istjc?'请选择要退订的教材':'是否订购教材', 
		                [{
		                    text: istjc?'确认':'确认',
		                    className:'bh-btn-warning',
		                    callback:function(){
		                    	var jcxx = '';
		                    	var dgjc = false;
	                    		$('#jcxx tbody tr').each(function(index,ele){
	                    			var firstSelect = $(ele).find('select').eq(0);
	                    			var sfdg = firstSelect.val();
	                    			var jcbh = firstSelect.attr('jcbh');
	                    			var dgyy = $(ele).find('select').eq(1).val();
	                    			if(istjc){
	                    				if(sfdg=='1'){
	                    					jcxx += ',' + jcbh + '-' + dgyy;
	                    				}
	                    			}else{
	                    				jcxx += ',' + jcbh + ((sfdg=='1')?'':('-' + dgyy));
	                    				if(sfdg=='1'){
	                    					dgjc = true;
	                    				}
	                    			}
	                    		});
		                    	if(!jcxx || jcxx.indexOf('***')>0 || (!istjc && !dgjc)){
                    				var _data = {};
                        			_data.title = '错误';
                        			if(jcxx.indexOf('***')>0){
                        				_data.content = '请确认需要退订的教材';
                        			}else{
                        				_data.content = istjc?'请确认需要退订的教材':'请确认需要订购的教材';
                        			}
                        			CVDialogSelectCourse.showDanger(_data);
                    			}else{
                    				e.jcxx = jcxx.substr(1);
                    				e.czlx = istjc?'0':'1';
                    				unbookJxbJc(e);
                    			}
		                    }
		                   },
		                   {
		                        text:'取消',
		                        className:'bh-btn-default',
		                        callback:function(){
		                        }
		                    }],
		                   {
		                        height: 400,
		                        width: 800
		        });
    		}else{
    			var _data = {};
    			_data.title = '错误';
    			_data.content = resp.msg || '查询教材错误';
    			CVDialogSelectCourse.showDanger(_data);
    		}
    		
    		
    	});
    }
    /**
     * 显示对话框
     * @param _data {object}
     * @param _data.title {string} 课程标题
     */
    function showDialog(_data, e) {
        var template =
            '<div id="cvDialog" class="cv-dialog @type">' +
            '<div>' +
            '<div class="cv-body">' +
            '<img class="cv-mb-16" src="public/images/curriculaVariable/dialog-icon.png">' +
            '<h2 class="cv-mb-8">@title</h2>' +
            '<div>@content</div>' +
            '</div>' +
            '<div class="cv-foot">' +
            '<div class="cv-sure cvBtnFlag" type="sure">确认</div>' +
            '<div class="cv-cancel cvBtnFlag" type="cancel">取消</div>' +
            '</div>' +
            '</div>' +
            '</div>';

        var title = _data.title;
        var content = _data.content;
        var html = template.replace('@title', title).replace('@content', content);

        var $dialog = $(html);
        $('body').append($dialog);

        //点击页脚按钮的事件
        $dialog.on('click', '.cvBtnFlag', function() {
            btnHandle($(this), e, _data.type);
        });
    }

    /**
     * 点击页脚按钮的事件
     * @param $btn 被点击的按钮
     */
    function btnHandle($btn, e, btnType) {
        var type = $btn.attr('type');
        //退选
        if (type === 'sure') {
            sureHandle(e, btnType);
        } else {
            //取消
            cancelHandle();
        }
    }

    /**
     * 取消
     */
    function cancelHandle() {
        removeDialog();
    }

    /**
     * 确认退选
     */
    function sureHandle(e, btnType) {
    	removeDialog();
    	if(btnType == 'course-book'){
    		//bookJxbJc(e);
    		unbookJxbJc(e);
    	}else if(btnType == 'course-unbook'){
    		unbookJxbJc(e);
    	}else {
    		deleteVolunteer(e);
    	}
    }

    /**
     * 移除弹框
     */
    function removeDialog() {
        $('#cvDialog').remove();
    }
    
    function bookJxbJc(e){
    	var teachingClassID = $(e.currentTarget).attr('teachingClassID');
    	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var studentCode = studentInfo.code; // 学号
        var electiveBatch = studentInfo.electiveBatch;
        var electiveBatchCode = electiveBatch.code;
        var addParam = {
    		xklcdm: electiveBatchCode,
    		xh: studentCode,
    		jxbid: teachingClassID
        };
        bookJxbJcResult(addParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                $('#cvDialog').remove();
                CVCourseResult.init();
                $.bhTip({
                    content: '订购教材成功',
                    state: 'success'
                });
            } else {
                var failObj = new Object();
                failObj.title = '失败';
                failObj.content = resp.msg;
                CVDialogSelectCourse.remove();
                CVDialogSelectCourse.showDanger(failObj);
            }
        });
    }
    
    function unbookJxbJc(e){
    	var teachingClassID = $(e.currentTarget).attr('teachingClassID');
    	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    	var studentCode = studentInfo.code; // 学号
    	var electiveBatch = studentInfo.electiveBatch;
    	var electiveBatchCode = electiveBatch.code;
    	var addParam = {
    			xklcdm: electiveBatchCode,
    			xh: studentCode,
    			jxbid: teachingClassID,
    			jcxx: e.jcxx,
    			czlx: e.czlx
    	};
    	delBookJxbJcResult(addParam).done(function(resp) {
    		var code = resp.code;
    		if (code != null && code == '1') {
    			$('#cvDialog').remove();
    			CVCourseResult.init();
    			$.bhTip({
    				content: '操作教材成功',
    				state: 'success'
    			});
    		} else {
    			var failObj = new Object();
    			failObj.title = '失败';
    			failObj.content = resp.msg;
    			CVDialogSelectCourse.remove();
    			CVDialogSelectCourse.showDanger(failObj);
    		}
    	});
    }

    function deleteVolunteer(e) {
        var teachingClassID = $(e.currentTarget).attr('teachingClassID');
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var studentCode = studentInfo.code; // 学号
        var electiveBatch = studentInfo.electiveBatch;
        var electiveBatchCode = electiveBatch.code;
        var delData = '{"operationType":"2"' + ',"studentCode":"' + studentCode + '"' + ',"electiveBatchCode":"' + electiveBatchCode + '"' + ',"teachingClassId":"' + teachingClassID + '"' + ',"isMajor":"1"}';
        var delStr = '{"data":' + delData + '}';
        var deleteParam = {
            'deleteParam': delStr
        };
        deleteVolunteerResult(deleteParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
            	$('#cvDialog').remove();
                initProcessInterval(function(processResp){
                	CVCourseResult.init();
                	if(processResp.code == '1'){
                		$.bhTip({
                			content: '删除选课成功',
                			state: 'success'
                		});
                	}else if(processResp.code == '-1'){
                		$.bhTip({
                			content: processResp.msg,
                			state: 'danger'
                		});
                	}
                	// 查询已选课程数量
                	querySelectCourseNum();
                });
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                var failObj = new Object();
                failObj.title = '失败';
                failObj.content = resp.msg;
                CVDialogSelectCourse.remove();
                CVDialogSelectCourse.showDanger(failObj);
            }
        });
    }
})(window.CVDialogSelectCourse = window.CVDialogSelectCourse || {});

function initSelectCourse() {
	var bookParam = JSON.parse(sessionStorage.getItem('bookParam'));
    if(bookParam.needBook != '1'){
    	$('#cvSelectCourse .cv-jcBook').hide();
    }
    
    var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
    if(sysParam.xgxkQueryTitle){
    	changeTskName(sysParam.xgxkQueryTitle);
    }
    if(sysParam.kclbNotDisplay == '1'){
    	$('#cvSelectCourse').addClass('no-kclb');
    }
    // 初始化学生选课结果
    CVCourseResult.init();
}

function changeJcWdgyy(ele, istjc){
	var v = $(ele);
	var flag = istjc?(v.val()!=='1'):(v.val()=='1');
	v.parent().next().children(0).prop("disabled", flag);
//	if(!istjc){
		v.parent().next().children(0).val("***");
//	}
}